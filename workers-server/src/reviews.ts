/**
 * reviews.ts — 거래 후기 · 매너 평가 규칙 (당근식). 서버 단일 진실원.
 *
 * 흐름 (앱의 ReviewSheet 와 같은 3단계):
 *   1) 평가: 'bad'(별로예요) / 'good'(좋아요) / 'best'(최고예요)
 *      'soso'(보통이에요)는 구버전 앱·예전 데이터 호환용으로만 남아 있다.
 *   2) 매너 항목: 평가가 긍정이면 칭찬 항목, 'bad' 면 비매너 항목. 역할(구매자가 판매자를
 *      평가 / 판매자가 구매자를 평가)마다 고를 수 있는 항목이 다르다. 최소 1개 필수.
 *      DB 에는 안정적인 코드('kind', 'late' …)를 CSV 로 저장하고, 앱이 언어별 문구로 보여준다.
 *   3) 후기 글 (선택, 최대 300자) — 욕설·혐오·외부 연락처는 거절.
 *
 * 공개 범위 (당근과 같음):
 *   'bad' 후기는 매너온도에만 반영되고 프로필 어디에도(항목·글·개수) 공개하지 않는다.
 */

export type ReviewRating = 'best' | 'good' | 'soso' | 'bad';
/** 후기를 쓰는 사람의 역할. 'buyer' = 구매자가 판매자를 평가. */
export type ReviewerRole = 'buyer' | 'seller';

/** 새 앱이 보낼 수 있는 평가. 'soso' 는 구버전 앱 요청에서만 받는다. */
export const NEW_RATINGS: ReviewRating[] = ['best', 'good', 'bad'];
export const LEGACY_RATINGS: ReviewRating[] = ['good', 'soso', 'bad'];

/**
 * 매너온도 변화량. users.manner_score 는 ×10 정수 스케일 (365 = 36.5°).
 *   최고예요 +0.5° / 좋아요 +0.2° / 보통이에요 0 / 별로예요 −0.5°
 */
export const MANNER_DELTA: Record<ReviewRating, number> = {
  best: 5,
  good: 2,
  soso: 0,
  bad: -5,
};
/** 매너온도 범위 0.0° ~ 99.0° (×10). 기존 코드와 같은 클램프. */
export const MANNER_MIN = 0;
export const MANNER_MAX = 990;

export const COMMENT_MAX = 300;
export const MAX_TAGS = 10;

// ── 매너 항목 코드 ─────────────────────────────────────────────────
// 칭찬 (rating = best | good)
const POS_COMMON = ['kind', 'punctual', 'fast_reply'];
/** 구매자 → 판매자 칭찬 */
const POS_FOR_SELLER = ['as_described', 'detailed_desc', 'good_price', 'free_share'];
/** 판매자 → 구매자 칭찬 */
const POS_FOR_BUYER = ['paid_on_time', 'no_haggle'];

// 비매너 (rating = bad)
const NEG_COMMON = ['late', 'slow_reply', 'rude', 'no_show'];
/** 구매자 → 판매자 비매너 */
const NEG_FOR_SELLER = ['not_as_described', 'price_change'];
/** 판매자 → 구매자 비매너 */
const NEG_FOR_BUYER = ['haggle'];

export const POSITIVE_CODES = new Set([...POS_COMMON, ...POS_FOR_SELLER, ...POS_FOR_BUYER]);
export const NEGATIVE_CODES = new Set([...NEG_COMMON, ...NEG_FOR_SELLER, ...NEG_FOR_BUYER]);

/** 역할·평가에 따라 고를 수 있는 항목 코드 (앱 화면 순서와 같음). */
export function allowedTags(role: ReviewerRole, rating: ReviewRating, opts: { free?: boolean } = {}): string[] {
  if (rating === 'bad') {
    return role === 'buyer' ? [...NEG_COMMON, ...NEG_FOR_SELLER] : [...NEG_COMMON, ...NEG_FOR_BUYER];
  }
  if (role === 'buyer') {
    // 무료나눔 칭찬은 가격 0원 상품에서만.
    const seller = POS_FOR_SELLER.filter((t) => t !== 'free_share' || opts.free);
    return [...POS_COMMON, ...seller];
  }
  return [...POS_COMMON, ...POS_FOR_BUYER];
}

/** 공개해도 되는 평가 — 'bad' 는 비공개. */
export const PUBLIC_RATINGS_SQL = "('best','good','soso')";

/** CSV → 코드 배열. */
export function splitTags(csv: string | null | undefined): string[] {
  if (!csv) return [];
  return csv.split(',').map((s) => s.trim()).filter(Boolean);
}
