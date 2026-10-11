/**
 * 한국/일본 시장 구분.
 *
 *   kr — 한국어 · 원(₩) · 한국 지역 · 1 QTA = 10원
 *   jp — 일본어 · 엔(¥) · 일본 지역 · 1 QTA = 1엔
 *
 * 회원의 시장은 가입 때 정해져 users.market 에 남는다 (앱이 기기 언어로 보냄).
 * 로그인 전 요청은 X-Market 헤더 → Accept-Language(ja) 순으로 추정한다.
 */
import type { Context } from 'hono';

export type Market = 'kr' | 'jp';

export function normalizeMarket(v: unknown): Market | null {
  return v === 'kr' || v === 'jp' ? v : null;
}

/** 접속 IP 의 나라 (Cloudflare 가 붙여 줌). 예: 'JP', 'KR'. 모르면 ''. */
export function ipCountry(c: Context): string {
  const cf = (c.req.raw as Request & { cf?: { country?: string } }).cf;
  return (cf?.country || c.req.header('cf-ipcountry') || '').toUpperCase();
}

/** 접속 IP 로 정한 시장 — 일본 IP 면 jp, 그 외는 kr. */
export function ipMarket(c: Context): Market {
  return ipCountry(c) === 'JP' ? 'jp' : 'kr';
}

/**
 * 로그인 전·응답 언어용 시장 추정.
 * 앱은 처음 실행 때 IP 로 정한 시장을 X-Market 으로 계속 보낸다. 헤더가 없으면 IP.
 */
export function requestMarket(c: Context): Market {
  const h = normalizeMarket((c.req.header('x-market') || '').trim().toLowerCase());
  if (h) return h;
  return ipMarket(c);
}

/** 응답 메시지 언어 선택. 한국어가 기본. */
export function tr(c: Context, ko: string, ja: string): string {
  return requestMarket(c) === 'jp' ? ja : ko;
}

/** 컨텍스트 없는 헬퍼에 넘기는 메시지 언어. */
export type Lang = 'ko' | 'ja';

/** 요청 기준 메시지 언어 — 헬퍼 함수의 lang 인자로 넘긴다. */
export function reqLang(c: Context): Lang {
  return requestMarket(c) === 'jp' ? 'ja' : 'ko';
}

/** 헬퍼용 tr — lang 으로 고른다. */
export function trl(lang: Lang, ko: string, ja: string): string {
  return lang === 'ja' ? ja : ko;
}

export const MARKET_CURRENCY: Record<Market, 'KRW' | 'JPY'> = { kr: 'KRW', jp: 'JPY' };

/** 현지 화폐 몇 단위가 1 QTA 인가. 원 10 / 엔 1 (10원 ≈ 1엔). */
export const MONEY_PER_QTA: Record<Market, number> = { kr: 10, jp: 1 };


/** 휴대폰 인증 허용 번호. 한국 010/011/016~019, 일본 070/080/090. */
export function isAllowedMobile(e164: string): boolean {
  return /^\+821[016789]\d{7,8}$/.test(e164) || /^\+81[789]0\d{8}$/.test(e164);
}
