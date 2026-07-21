#!/usr/bin/env bash
set -euo pipefail

# Codex 리뷰와 Claude 수정을 로컬에서 제한된 횟수만큼 왕복한다.
# 무한 루프 방지:
# - 기본 최대 3회만 반복한다.
# - Codex가 조치할 결함이 없다고 하면 종료한다.
# - Claude 실행 후 커밋할 변경사항이 없으면 종료한다.
# - 루프가 만든 커밋에서는 post-commit 훅을 건너뛰어 중복 리뷰를 막는다.
#
# 사용법:
#   scripts/ai-review-loop.sh
#   scripts/ai-review-loop.sh --max 5

repo_root=$(git rev-parse --show-toplevel)
review_dir="$repo_root/.ai-review"
mkdir -p "$review_dir"

max_iterations=3
while [ $# -gt 0 ]; do
    case "$1" in
        --max)
            shift
            if [ $# -eq 0 ]; then
                echo "--max에는 반복 횟수가 필요합니다." >&2
                exit 2
            fi
            max_iterations="$1"
            ;;
        *)
            echo "알 수 없는 옵션: $1" >&2
            exit 2
            ;;
    esac
    shift
done

if ! [[ "$max_iterations" =~ ^[1-9][0-9]*$ ]]; then
    echo "--max는 1 이상의 정수여야 합니다." >&2
    exit 2
fi

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "$1 CLI를 찾을 수 없습니다." >&2
        exit 127
    fi
}

review_has_no_actionable_findings() {
    # "no issues" 계열 문구를 파일 전체에서 찾는 방식은 위험하다 — 실제 지적의 설명 문장이 그
    # 문구를 예시로 인용하기만 해도(예: "API가 no findings를 반환하면 크래시한다") 오탐으로
    # 진짜 지적을 놓친다. 반대로 "- [P#] ..." 불릿 자체를 파일 전체에서 찾는 것도 위험하다 —
    # 이 스크립트는 자기 자신의 리뷰 판정 로직을 계속 리뷰받으므로, "조치할 거 없음" 리뷰가
    # 이 불릿 형식 자체를 설명하며 예시로 인용하면(예: "표준 형식이 `- [P2] example`이다") 그
    # 예시 텍스트가 실제 지적으로 오판되어 불필요하게 Claude가 실행된다.
    # codex는 실제 조치 항목이 있을 때만 "Review comment:" 섹션 뒤에 "- [P#] ..." 불릿을
    # 붙인다 — 그 섹션 헤더 이후에서만 불릿을 찾아 예시 인용과 실제 지적을 구분한다.
    if ! grep -qi '^Review comment:' "$review_dir/codex-review.md"; then
        return 0
    fi
    ! awk 'tolower($0) ~ /^review comment:/{flag=1} flag' "$review_dir/codex-review.md" \
        | grep -qE '^[[:space:]]*-[[:space:]]*\[P[0-9]+\]'
}

# git diff/--cached만 보면 새로 만든(아직 add 안 된 untracked) 파일은 안 잡힌다 — Claude가
# 새 파일로 고친 수정이 "변경 없음"으로 오판되어 커밋도 안 되고 통째로 유실된다.
# status --porcelain은 untracked까지 포함해서 잡는다.
has_uncommitted_changes() {
    [ -n "$(git status --porcelain)" ]
}

require_command codex
require_command claude

cd "$repo_root"

if has_uncommitted_changes; then
    echo "작업 트리에 커밋되지 않은 변경사항이 있습니다. 먼저 커밋하거나 정리한 뒤 실행하세요." >&2
    exit 1
fi

for iteration in $(seq 1 "$max_iterations"); do
    sha=$(git rev-parse HEAD)
    echo "[$iteration/$max_iterations] Codex 리뷰 실행: $sha"
    codex exec review --commit "$sha" -o "$review_dir/codex-review.md"

    if review_has_no_actionable_findings; then
        echo "Codex가 조치할 결함이 없다고 판단했습니다. 루프를 종료합니다."
        exit 0
    fi

    echo "[$iteration/$max_iterations] Claude 수정 실행"
    claude -p --permission-mode acceptEdits "
You are fixing issues from an automated Codex code review for this repository.

Before deciding, read AGENTS.md, PRD.md, docs/*.md, and .ai-review/codex-review.md.
Treat items documented as unimplemented, non-goals, or intentional replacements as non-issues.

If the review contains a valid actionable defect, implement the smallest safe fix following the
repository rules. Run focused verification when practical. Do not commit.

If the review is invalid or needs more context, do not edit code.

Write a concise Korean response addressed to Codex, including what you changed or why you did not
change anything.
" > "$review_dir/claude-response.md"

    if ! has_uncommitted_changes; then
        echo "Claude가 커밋할 변경사항을 만들지 않았습니다. 루프를 종료합니다."
        exit 0
    fi

    git add -A
    AI_REVIEW_SKIP_HOOK=1 git commit -m "ai-fix: address Codex review feedback"
done

echo "최대 반복 횟수($max_iterations)에 도달했습니다. 마지막 Codex 리뷰를 확인하세요: $review_dir/codex-review.md"
