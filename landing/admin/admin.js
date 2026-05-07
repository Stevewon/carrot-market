/* ============================================================
 * Eggplant Admin Console — common JS
 * 토큰 관리, API 호출, 사이드바 렌더링, 유틸리티
 * ============================================================ */

(function () {
  'use strict';

  const API_BASE = (function () {
    // 같은 도메인이면 상대경로, 아니면 api 서브도메인
    const host = location.host;
    if (host === 'eggplant.life' || host.endsWith('.eggplant.life')) {
      return 'https://api.eggplant.life';
    }
    // 로컬/Pages 도메인 등 — 풀 URL 으로 접근
    return 'https://api.eggplant.life';
  })();

  const TOKEN_KEY = 'eggplant_admin_token';
  const ADMIN_KEY = 'eggplant_admin_info';

  function getToken() { return localStorage.getItem(TOKEN_KEY) || ''; }
  function setToken(t) { localStorage.setItem(TOKEN_KEY, t); }
  function clearToken() { localStorage.removeItem(TOKEN_KEY); localStorage.removeItem(ADMIN_KEY); }
  function getAdminInfo() {
    try { return JSON.parse(localStorage.getItem(ADMIN_KEY) || 'null'); }
    catch { return null; }
  }
  function setAdminInfo(info) { localStorage.setItem(ADMIN_KEY, JSON.stringify(info)); }

  /** API 호출 — 토큰 자동 첨부, 401 시 로그인으로 리다이렉트 */
  async function api(path, options) {
    options = options || {};
    const headers = Object.assign(
      { 'Content-Type': 'application/json' },
      options.headers || {},
    );
    const token = getToken();
    if (token) headers['Authorization'] = 'Bearer ' + token;

    const res = await fetch(API_BASE + path, {
      method: options.method || 'GET',
      headers,
      body: options.body ? JSON.stringify(options.body) : undefined,
    });

    if (res.status === 401 && !path.endsWith('/admin/login')) {
      clearToken();
      location.href = '/admin/login.html';
      throw new Error('401 Unauthorized');
    }

    let data;
    try { data = await res.json(); }
    catch { data = null; }

    if (!res.ok) {
      const msg = (data && data.error) || ('HTTP ' + res.status);
      const err = new Error(msg);
      err.status = res.status;
      err.data = data;
      throw err;
    }
    return data;
  }

  /** 현재 페이지 슬러그 추출 (login/index/users/products/...) */
  function currentPage() {
    const f = location.pathname.split('/').pop() || 'index.html';
    return f.replace('.html', '') || 'index';
  }

  /** 사이드바 렌더링 — 모든 admin 페이지에서 공통 호출 */
  function renderSidebar(target) {
    const slug = currentPage();
    const items = [
      { href: 'index.html',       slug: 'index',       label: '대시보드',   icon: '📊' },
      { href: 'withdrawals.html', slug: 'withdrawals', label: '출금 신청',  icon: '💸' },
      { href: 'reports.html',     slug: 'reports',     label: '신고 처리',  icon: '🚨' },
      { href: 'users.html',       slug: 'users',       label: '사용자',     icon: '👥' },
      { href: 'products.html',    slug: 'products',    label: '상품',       icon: '🛍️' },
      { href: 'stats.html',       slug: 'stats',       label: '감사 로그',  icon: '📜' },
    ];
    const me = getAdminInfo();
    const meHtml = me ?
      `<small>${escapeHtml(me.username || '')} · ${escapeHtml(me.role || 'admin')}</small>` :
      '';

    target.innerHTML = `
      <div class="brand">🍆 Eggplant Admin ${meHtml}</div>
      <nav>
        ${items.map(i => `
          <a href="${i.href}" class="${i.slug === slug ? 'active' : ''}">
            <span>${i.icon}</span><span>${i.label}</span>
          </a>`).join('')}
        <a href="#" id="admin-logout" style="margin-top: 16px; color: #f87171;">
          <span>🚪</span><span>로그아웃</span>
        </a>
      </nav>
    `;
    const btn = target.querySelector('#admin-logout');
    if (btn) btn.addEventListener('click', async (e) => {
      e.preventDefault();
      try { await api('/api/admin/logout', { method: 'POST' }); }
      catch { /* ignore */ }
      clearToken();
      location.href = '/admin/login.html';
    });
  }

  /** 헤더 영역에 본인 정보 표시 */
  function renderHeaderMe(target) {
    const me = getAdminInfo();
    if (!me) return;
    target.innerHTML = `<span class="me">로그인: <b>${escapeHtml(me.username)}</b> (${escapeHtml(me.role)})</span>`;
  }

  /** 인증 상태 가드 — 토큰 없으면 로그인 페이지로 */
  function requireAuth() {
    if (!getToken()) {
      location.href = '/admin/login.html';
      return false;
    }
    return true;
  }

  /** 안전한 HTML 이스케이프 */
  function escapeHtml(s) {
    if (s === null || s === undefined) return '';
    return String(s)
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  }

  /** 날짜 포맷 (YYYY-MM-DD HH:mm) */
  function fmtDate(s) {
    if (!s) return '';
    // SQLite datetime is 'YYYY-MM-DD HH:MM:SS' in UTC
    return String(s).replace('T', ' ').slice(0, 16);
  }

  /** 숫자 포맷 (천단위 콤마) */
  function fmtNum(n) {
    if (n === null || n === undefined) return '0';
    return Number(n).toLocaleString('ko-KR');
  }

  /** 짧은 ID 표시 (앞 8자리) */
  function shortId(id) {
    if (!id) return '';
    return String(id).slice(0, 8);
  }

  /** 로딩/에러/빈 상태 헬퍼 */
  function showLoading(el) { el.innerHTML = '<div class="loading">불러오는 중</div>'; }
  function showError(el, msg) { el.innerHTML = `<div class="error-box">⚠️ ${escapeHtml(msg)}</div>`; }
  function showEmpty(el, msg) { el.innerHTML = `<div class="empty">${escapeHtml(msg || '데이터 없음')}</div>`; }

  /** 모달 열기/닫기 */
  function openModal(id) {
    const m = document.getElementById(id);
    if (m) m.classList.add('show');
  }
  function closeModal(id) {
    const m = document.getElementById(id);
    if (m) m.classList.remove('show');
  }

  /** 확인 다이얼로그 (네이티브 confirm 래퍼) */
  function confirmDanger(msg) {
    return window.confirm(msg);
  }

  // 모달 backdrop 클릭 시 닫기
  document.addEventListener('click', (e) => {
    if (e.target && e.target.classList && e.target.classList.contains('modal-backdrop')) {
      e.target.classList.remove('show');
    }
  });

  // 전역 네임스페이스 노출
  window.AdminApp = {
    API_BASE,
    api,
    getToken, setToken, clearToken,
    getAdminInfo, setAdminInfo,
    renderSidebar,
    renderHeaderMe,
    requireAuth,
    escapeHtml,
    fmtDate,
    fmtNum,
    shortId,
    showLoading,
    showError,
    showEmpty,
    openModal,
    closeModal,
    confirmDanger,
  };
})();
