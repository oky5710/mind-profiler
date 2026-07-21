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
    # 진짜 지적을 놓친다. 실제로 이 방식 때문에 바로 이전 리뷰(scripts/ai-review-loop.sh를
    # 다루는 P2 지적)가 그 지적 문장 안에 "no findings"라는 표현이 들어 있어서 조치할 게
    # 없다고 잘못 판정되어 루프가 조용히 종료된 적이 있다.
    # 대신 codex가 실제 조치 항목마다 반드시 붙이는 "- [P#] 제목 — 파일:줄" 형식의 불릿
    # 자체가 있는지만 본다 — 이 불릿은 문장 안에 우연히 나타날 수 없는 구조적 표식이다.
    ! grep -qE '^[[:space:]]*-[[:space:]]*\[P[0-9]+\]' "$review_dir/codex-review.md"
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
