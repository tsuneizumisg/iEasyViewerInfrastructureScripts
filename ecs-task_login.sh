#!/bin/bash
#------------------------------------------------------------------------------------------
# 【概要】
# ECSタスクにログインするスクリプト
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
# 1.コンソールから確認したECSタスクのランタイムIDを確認
# 
# 2.クラスター名とランタイムIDを引数としてスクリプトを実行
# $ sh ecs-task_login.sh <CLUSTER_NAME> <RUNTIME_ID>
# ---------------------------------------------
# 
# 実行例
# $ sh ecs-task_login.sh iev-dv-cluster-bastion ed8cd7cdb51c498fbd7aee14cdf7ed23-3991252295
#------------------------------------------------------------------------------------------

# 引数チェック
if [ $# -ne 2 ]; then
  echo "Usage: $0 <CLUSTER_NAME> or <RUNTIME_ID>"
  exit 1
fi

# 引数から CLUSTER_NAME を取得
CLUSTER_NAME="$1"

# 引数から RUNTIME_ID を取得
RUNTIME_ID="$2"

# TASK_ID は RUNTIME_ID の最初のハイフン（-）の前を削除して取り出す
# 例: ed8cd7cdb51c498fbd7aee14cdf7ed23-3991252295 → ed8cd7cdb51c498fbd7aee14cdf7ed23
TASK_ID="${RUNTIME_ID%%-*}"

# ECSタスクにログイン
/usr/local/bin/aws ssm start-session \
  --region ap-northeast-1 \
  --target ecs:${CLUSTER_NAME}_${TASK_ID}_${RUNTIME_ID}