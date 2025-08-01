#!/bin/bash
#------------------------------------------------------------------------------------------
# 【概要】
# ECSタスク(batch)を起動するスクリプト
# 
# 【スクリプト実行内容】
# ① ecsタスクを終了するための関数を設定（Ctrl+Cなどで終了）
# ② 踏み台となるecsタスクを起動
# 
# 【事前準備】
# ---------------------------------------------
# 1. WorkSpaces環境にAWS CLI v2バージョンをインストール
#    https://docs.aws.amazon.com/ja_jp/cli/latest/userguide/getting-started-install.html
# 
# 2. WorkSpaces環境に本スクリプトを配置
# ---------------------------------------------
# 
# 【実行手順】
# ---------------------------------------------
# 1. 「AWSアクセスポータル（AWS access portal）」にてアクセスキーを取得（「オプション 1: AWS の環境変数を設定する」をコピー）して、ターミナルに適用
# 
# 2. スクリプト内に記載された環境変数を編集（必要な場合のみ）
# 
# 3. スクリプト実行 ※①②の処理が行われる
#   $ iev-dv-batch_ecs-task-start.sh
# ---------------------------------------------
#------------------------------------------------------------------------------------------

# 環境情報設定(RDSのホスト名,ポート番号は直接指定)
CLUSTER_NAME=iev-dv-cluster-batch
TASK_DEFINITION=iev-dv-task-definition-batch
SECURITYGROUP_ID=sg-097a6adf8be491963
SUBNET_ID=subnet-0961911b2e8504554

############ ① ecsタスクを終了するための関数を設定（Ctrl+Cなどで終了） ############
function stop_container () {
  echo 'Stopping ecs bastion container'
  /usr/local/bin/aws ecs stop-task \
    --cluster $CLUSTER_NAME \
    --task  $TASK_ID >/dev/null
  TASK_STATUS=$(/usr/local/bin/aws ecs describe-tasks \
    --cluster $CLUSTER_NAME \
    --tasks  $TASK_ID | jq -r '.tasks[0].desiredStatus')
  if [ $TASK_STATUS = "STOPPED" ]; then
    echo "Container is stopping"
  else
    echo "Container is not stopping. Check the container status from aws console"
  fi
  exit 1
}

############ ② 踏み台となるecsタスクを起動 ############
# タスク定義のARN取得（最新バージョンを使用する場合）
TASK_DEFINITION_ARN=$(/usr/local/bin/aws ecs describe-task-definition \
  --task-definition $TASK_DEFINITION | jq -r '.taskDefinition.taskDefinitionArn')

# タスク定義のARN指定（任意のバージョンを使用する場合）
# TASK_DEFINITION_ARN=arn:aws:ecs:ap-northeast-1:616749751767:task-definition/iev-dv-task-definition-bastion:3
echo "TASK_DEFINITION_ARN: ${TASK_DEFINITION_ARN}"

# 踏み台コンテナを起動
echo "Running ecs bastion container..."
RESPONSE=$(/usr/local/bin/aws ecs run-task \
  --cluster $CLUSTER_NAME \
  --count 1 \
  --enable-execute-command \
  --launch-type FARGATE \
  --network-configuration 'awsvpcConfiguration={subnets=['$SUBNET_ID'],securityGroups=['$SECURITYGROUP_ID'],assignPublicIp=DISABLED}' \
  --platform-version 1.4.0 \
  --propagate-tags TASK_DEFINITION \
  --task-definition $TASK_DEFINITION_ARN)
  # --capacity-provider-strategy capacityProvider=FARGATE_SPOT,weight=1 \
echo "RESPONSE: ${RESPONSE}"

# タスクIDを取得
TASK_ID=$(echo $RESPONSE | jq -r '.tasks[0].taskArn' | awk -F'[/]' '{print $3}')
echo "TASK_ID: ${TASK_ID}"

# 起動したタスクの情報を取得
TASK_INFO=$(/usr/local/bin/aws ecs describe-tasks \
  --cluster $CLUSTER_NAME \
  --tasks  $TASK_ID)
TASK_STATUS=$(echo $TASK_INFO | jq -r '.tasks[0].lastStatus')

# コンテナが起動するまで待機
while [ $TASK_STATUS != "RUNNING" ]
do
  sleep 10
  TASK_INFO=$(/usr/local/bin/aws ecs describe-tasks \
    --cluster $CLUSTER_NAME \
    --tasks  $TASK_ID)
  TASK_STATUS=$(echo $TASK_INFO | jq -r '.tasks[0].lastStatus')
  RUNTIME_ID=$(echo $TASK_INFO | jq -r '.tasks[0].containers[0].runtimeId')
  echo "Waiting for container status is running..."
done
echo "TASK_INFO: ${TASK_INFO}"
echo "TASK_STATUS: ${TASK_STATUS}"
echo "RUNTIME_ID: ${RUNTIME_ID}"

# Ctrl+Cなどで終了したらExit処理する
trap 'stop_container' {1,2,9,20}

