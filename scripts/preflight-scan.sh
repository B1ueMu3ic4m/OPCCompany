#!/bin/bash
# OPCCompany 发布前敏感信息侦察(只输出文件名和计数,绝不输出内容本身)
cd ~/Desktop/OPCCompany || exit 1
EX="--exclude-dir=.build --exclude-dir=dist --exclude-dir=.ccb --exclude-dir=.claude --exclude-dir=.git"

echo "=== A. 体积与文件量 ==="
du -sh . 2>/dev/null
du -sh .build dist .ccb .claude 2>/dev/null
echo "files_total: $(find . -type f 2>/dev/null | wc -l | tr -d ' ')"
echo "files_publishable_scope: $(find . -type f -not -path './.build/*' -not -path './dist/*' -not -path './.ccb/*' -not -path './.claude/*' -not -path './.git/*' 2>/dev/null | wc -l | tr -d ' ')"

echo "=== B. 硬秘密模式(文件数 + 文件名,前8) ==="
declare -a PATTERNS=(
  'sk-[A-Za-z0-9_-]{10,}'
  'gh[pousr]_[A-Za-z0-9]{20,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  'AKIA[0-9A-Z]{16}'
  'AIza[0-9A-Za-z_-]{30,}'
  'BEGIN [A-Z ]*PRIVATE KEY'
  'xox[baprs]-'
)
for p in "${PATTERNS[@]}"; do
  files=$(grep -rIlE "$p" . $EX 2>/dev/null)
  n=$(echo "$files" | grep -c . )
  echo "pattern[$p] -> $n files"
  [ "$n" != "0" ] && echo "$files" | head -8
done

echo "=== C. VPS/代理/基础设施特征 ==="
declare -a INFRA=(
  'BandwagonHost|DMIT|vps-inventory'
  'VLESS|Reality|Trojan|HY2'
  '科学上网|订阅地址'
)
for p in "${INFRA[@]}"; do
  files=$(grep -rIlE "$p" . $EX 2>/dev/null)
  n=$(echo "$files" | grep -c . )
  echo "infra[$p] -> $n files"
  [ "$n" != "0" ] && echo "$files" | head -8
done

echo "=== D. 订阅/账号信息特征 ==="
grep -rIliE 'chatgpt plus|claude max|claude pro|oauth|logged in as|account email' . $EX 2>/dev/null | head -10

echo "=== E. 硬编码主目录路径暴露(文件数+清单) ==="
n=$(grep -rIlE '/Users/[A-Za-z0-9._-]+' . $EX 2>/dev/null | wc -l | tr -d ' ')
echo "files with hardcoded /Users/<name> paths: $n"
grep -rIlE '/Users/[A-Za-z0-9._-]+' . $EX 2>/dev/null | head -15

echo "=== F. 邮箱形态(计数排序,前10) ==="
grep -rIhoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.(com|cn|net|org|io|dev|ai)' . $EX 2>/dev/null | sort | uniq -c | sort -rn | head -10

echo "=== G. 中国大陆手机号形态(文件数) ==="
grep -rIlE '1[3-9][0-9]{9}' . $EX 2>/dev/null | head -8

echo "=== H. 大文件>2MB(排除构建产物) ==="
find . -type f -size +2M -not -path './.build/*' -not -path './.ccb/*' -not -path './.claude/*' 2>/dev/null -exec du -h {} \; | head -8

echo "=== I. 工具链可用性 ==="
for t in ffmpeg gitleaks brew gh git sips osascript; do
  command -v $t >/dev/null 2>&1 && echo "$t: ok" || echo "$t: MISSING"
done

echo "=== J. .claude/.ccb 目录风险画像(仅文件数与体积) ==="
echo ".claude files: $(find .claude -type f 2>/dev/null | wc -l | tr -d ' '), size: $(du -sh .claude 2>/dev/null | cut -f1)"
echo ".ccb files: $(find .ccb -type f 2>/dev/null | wc -l | tr -d ' '), size: $(du -sh .ccb 2>/dev/null | cut -f1)"
echo "DONE"
