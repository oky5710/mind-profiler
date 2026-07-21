#!/usr/bin/env bash
set -euo pipefail

# codex CLI로 현재 변경사항을 리뷰받아 .ai-review/codex-review.md에 저장한다.
# 이후 Claude가 그 파일을 읽고 .ai-review/claude-response.md에 응답을 쓰는 식으로 주고받는다.
# git commit을 하면 scripts/hooks/post-commit(설치본: .git/hooks/post-commit)이 이 스크립트를
# --commit <방금 만든 커밋>으로 자동 호출하므로, 보통은 직접 실행할 필요 없이 커밋만 하면 된다.
#
# 사용법:
#   scripts/ai-review.sh                  # uncommitted 변경사항(staged+unstaged+untracked) 리뷰
#   scripts/ai-review.sh --base main       # main 브랜치 대비 변경사항 리뷰
#   scripts/ai-review.sh --commit <sha>    # 특정 커밋 리뷰
#   scripts/ai-review.sh "보안 관점에서만" # codex에게 추가 리뷰 지시사항 전달 (codex review [PROMPT])

repo_root=$(git rev-parse --show-toplevel)
review_dir="$repo_root/.ai-review"
mkdir -p "$review_dir"

review_args=("$@")
if [ ${#review_args[@]} -eq 0 ]; then
    review_args=(--uncommitted)
fi

codex exec review "${review_args[@]}" -o "$review_dir/codex-review.md"

echo "codex 리뷰 저장됨: $review_dir/codex-review.md"
