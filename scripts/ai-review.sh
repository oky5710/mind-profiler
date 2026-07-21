#!/usr/bin/env bash
set -euo pipefail

# codex CLI로 현재 변경사항을 리뷰받아 .ai-review/codex-review.md에 저장한다.
# 이후 Claude CLI가 그 파일을 읽고 .ai-review/claude-response.md에 자동 응답한다.
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

if command -v claude >/dev/null 2>&1; then
    claude -p "
You are responding to an automated Codex code review for this repository.

Read AGENTS.md, PRD.md, docs/*.md, and .ai-review/codex-review.md before responding.
Treat items documented as unimplemented, non-goals, or intentional replacements as non-issues.

Write a concise Korean response addressed to Codex. For each finding, say whether you agree,
disagree, or need more context. If you agree, mention the intended fix at a high level.
Do not edit repository files.
" > "$review_dir/claude-response.md"
    echo "Claude 응답 저장됨: $review_dir/claude-response.md"
else
    echo "claude CLI를 찾을 수 없어 Claude 자동 응답을 건너뜀"
fi
