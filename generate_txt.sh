#!/bin/bash

DOMAINS_FILE="domains.txt"  # 包含域名的文件
ACME=~/.acme.sh/acme.sh     # acme.sh 腳本的路徑
OUTPUT_CERT_DIR="./certs"   # 儲存證書的目錄
OUTPUT_KEY_DIR="./keys"     # 儲存密鑰的目錄
CHALLENGE_FILE="dns_challenges.txt"  # 儲存 TXT 記錄的文件

# 创建目录用于存储证书和密钥
mkdir -p "$OUTPUT_CERT_DIR" "$OUTPUT_KEY_DIR"

# 强制使用 Let's Encrypt 作為 CA
export CA="https://acme-v02.api.letsencrypt.org/directory"

echo "🔍 開始生成 DNS TXT 記錄..."

# 只生成一次 TXT 記錄並保存到文件
for domain in $(cat "$DOMAINS_FILE"); do
  echo "▶️ 處理：$domain"
  
  # 清除之前的挑戰紀錄（避免干擾）
  rm -rf ~/.acme.sh/$domain

  # 使用 acme.sh 啟動 DNS 驗證模式，並只生成 TXT 記錄
  export ACME_DNS_MANUAL_FORCE=1
  export LE_WORKING_DIR=~/.acme.sh

  # 執行一次會輸出要加的 TXT 記錄
  CHALLENGE_OUTPUT=$($ACME --issue --dns -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please --force --server https://acme-v02.api.letsencrypt.org/directory 2>&1)

  # 打印 acme.sh 的輸出以調試
  echo "$CHALLENGE_OUTPUT"

  # 擷取 TXT 值
  TXT_RECORD=$(echo "$CHALLENGE_OUTPUT" | grep -oP "(\b[A-Za-z0-9_\-]{43,}\b)")

  if [[ -n "$TXT_RECORD" ]]; then
    # 去除 * 字符
    DOMAIN_NO_WILDCARD=${domain//\*/}

    # 如果域名以 . 開頭或結尾（像 *.example.com），去除多餘的點
    if [[ "$DOMAIN_NO_WILDCARD" =~ ^\. ]]; then
      DOMAIN_NO_WILDCARD=${DOMAIN_NO_WILDCARD:1}
    fi
    if [[ "$DOMAIN_NO_WILDCARD" =~ \.$ ]]; then
      DOMAIN_NO_WILDCARD=${DOMAIN_NO_WILDCARD%?}
    fi

    # 確保 `_acme-challenge` 和域名之間只有一個點，沒有多餘的點
    DOMAIN_NO_WILDCARD=$(echo "$DOMAIN_NO_WILDCARD" | sed 's/\.\./\./g')  # 如果有兩個連接的點（..），就去掉

    # 輸出 TXT 記錄到文件
    echo "用戶：$domain" >> "$CHALLENGE_FILE"
    echo "請加 TXT 記錄：" >> "$CHALLENGE_FILE"
    echo "  名稱：_acme-challenge.$DOMAIN_NO_WILDCARD" >> "$CHALLENGE_FILE"
    echo "  值：  $TXT_RECORD" >> "$CHALLENGE_FILE"
    echo "-------------------------------" >> "$CHALLENGE_FILE"
    echo "✅ 已記錄 $domain 的挑戰"
  else
    echo "❌ 無法擷取 $domain 的 TXT 記錄，請檢查輸出"
    echo "$CHALLENGE_OUTPUT" > "error_$domain.txt"
  fi
done

echo "📂 所有挑戰記錄已寫入：$CHALLENGE_FILE"
echo "⏳ 請確認 DNS TXT 記錄已生效，按 Enter 鍵繼續簽發憑證"
read -p "按 Enter 繼續..."

# 确保 DNS TXT 记录已生效后，再进行证书签发
echo "🔍 開始驗證用戶的 DNS TXT 記錄並完成簽發..."

for domain in $(cat "$DOMAINS_FILE"); do
  echo "▶️ 處理：$domain"

  # 嘗試完成簽發流程（跳過 TXT 生成，直接檢查 DNS 記錄）
  $ACME --renew --dns -d "$domain" \
    --yes-I-know-dns-manual-mode-enough-go-ahead-please \
    --force --server https://acme-v02.api.letsencrypt.org/directory

  if [ $? -eq 0 ]; then
    echo "✅ 簽發成功：$domain"

    # 为证书和密钥指定存储路径
    FULLCHAIN_PATH="$OUTPUT_CERT_DIR/$domain.fullchain.crt"  # 完整链证书路径
    KEY_PATH="$OUTPUT_KEY_DIR/$domain.key"    # 密钥文件路径

    # 安装证书，并只保存 fullchain 文件
    $ACME --install-cert -d "$domain" \
      --fullchain-file "$FULLCHAIN_PATH" \
      --key-file "$KEY_PATH" \
      --ca-file /dev/null  # 不保存 CA 文件

    echo "📦 完整链证书儲存於：$FULLCHAIN_PATH 和 密鑰儲存於：$KEY_PATH"
  else
    echo "❌ 簽發失敗：$domain，請確認 TXT 記錄是否正確"
  fi

  echo "-----------------------------"
done

echo "✅ 所有處理完成"

