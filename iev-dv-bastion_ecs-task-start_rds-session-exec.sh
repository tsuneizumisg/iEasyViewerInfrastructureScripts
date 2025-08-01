#!/bin/bash
#------------------------------------------------------------------------------------------
# 【概要】
# 起動したECSタスク(bastion)からRDS（Aurora）に接続するための環境を提供するスクリプト
# 
# 【スクリプト実行内容】
# ① ecsタスクを終了するための関数を設定（Ctrl+Cなどで終了）
# ② 踏み台となるecsタスクを起動
# ③ リモートホスト（RDS）へのポートフォワーディング
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
# 3. スクリプト実行 ※①②③の処理が行われる
#   $ iev-dv-bastion_ecs-task-start_rds-session-exec.sh
# 
# 4. 別ターミナルを起動して、データベース接続(PostgreSQL)
# 　$ psql -h localhost -p (ローカルポート番号) -d (DB名) -U (マスターユーザ名)
# 　(例)$ psql -h localhost -p 13306 -d iev_dv -U iev_dv_master
# 
# タスク終了：Ctrl+Cなどで終了
# ---------------------------------------------
# 
# 参考URL
# https://blog.dcs.co.jp/aws/20221124-serverless-bastion.html
# 
#------------------------------------------------------------------------------------------

# 環境情報設定(RDSのホスト名,ポート番号は直接指定)
CLUSTER_NAME=iev-dv-cluster-bastion
TASK_DEFINITION=iev-dv-task-definition-bastion
SECURITYGROUP_ID=sg-097a6adf8be491963
SUBNET_ID=subnet-0961911b2e8504554
RDS_HOST=iev-dv-db-cluster.cluster-c5y8ckgc4nps.ap-northeast-1.rds.amazonaws.com

# Aurora postgresqlエンジンが5432から3306になった様子
# https://blog.serverworks.co.jp/amazon-aurora-postgresql-limitless-database-cloudformation-template
# RDS_PORT="5432"
# LOCAL_PORT="15432"
RDS_PORT="3306"
LOCAL_PORT="13306"

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

# 直ぐに開始するとエラーになるため待機
sleep 5

# Ctrl+Cなどで終了したらExit処理する
trap 'stop_container' {1,2,9,20}

############ ③ リモートホスト（RDS）へのポートフォワーディング ############
# コンテナへのポートフォワーディング開始（socat使用の場合）
# /usr/local/bin/aws ssm start-session \
#   --target ecs:${CLUSTER_NAME}_${TASK_ID}_${RUNTIME_ID} \
#   --document-name AWS-StartPortForwardingSession \
#   --parameters '{"portNumber":["5432"],"localPortNumber":["5432"]}'

# 2022年5月にSession Managerがリモートホストへポートフォワーディング可能となったため以下に修正
# https://zenn.dev/quiver/articles/1458e453118254
# /usr/local/bin/aws ssm start-session --target <ターゲット名> \
#   --document-name AWS-StartPortForwardingSessionToRemoteHost \
#   --parameters '{"host":["RDSのホスト名"],"portNumber":["5432"], "localPortNumber":["12345"]}'

/usr/local/bin/aws ssm start-session \
  --target ecs:${CLUSTER_NAME}_${TASK_ID}_${RUNTIME_ID} \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"${RDS_HOST}\"],\"portNumber\":[\"${RDS_PORT}\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}"
