/**
 * Eggplant Admin Console — Main router & API helper
 *
 * 외부 의존 0 (Vanilla JS). Cloudflare Pages 정적 배포 그대로 동작.
 * 모든 API 호출은 Authorization: Admin <token> 헤더 자동 첨부.
 */
(function () {
  'use strict';

  // 백엔드 API base. 환경별로 바꾸려면 admin-web/config.js 만들어 override.
  const API_BASE = (window.__ADMIN_API_BASE__ || 'https://api.eggplant.life').replace(/\/$/, '');
  const TOKEN_KEY = 'eggplant_admin_token';
  const MIN_PC_WIDTH = 1024;

  const state = {
    token: null,
    currentRoute: null,
  };

  // ────────────────────────────────────────────────────────
  // PC 가드
  // ────────────────────────────────────────────────────────
  function isPC() {
    return window.innerWidth >= MIN_PC_WIDTH;
  }

  function applyPCGuard() {
    const guard = document.getElementById('pcGuard');
    const login = document.getElementById('loginView');
    const app = document.getElementById('appView');
    if (!isPC()) {
      guard.classList.remove('hidden');
      login.classList.add('hidden');
      app.classList.add('hidden');
      return false;
    }
    guard.classList.add('hidden');
    return true;
  }

  // ────────────────────────────────────────────────────────
  // 토큰 관리 (sessionStorage — 탭 닫으면 사라짐)
  // ────────────────────────────────────────────────────────
  function loadToken() {
    state.token = sessionStorage.getItem(TOKEN_KEY) || null;
    return state.token;
  }
  function saveToken(t) {
    state.token = t;
    sessionStorage.setItem(TOKEN_KEY, t);
  }
  function clearToken() {
    state.token = null;
    sessionStorage.removeItem(TOKEN_KEY);
  }

  // ────────────────────────────────────────────────────────
  // API 호출 헬퍼
  // ────────────────────────────────────────────────────────
  async function api(method, path, body) {
    const opts = {
      method,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Admin ${state.token || ''}`,
      },
    };
    if (body !== undefined) opts.body = JSON.stringify(body);

    let res;
    try {
      res = await fetch(`${API_BASE}${path}`, opts);
    } catch (e) {
      throw new Error('네트워크 오류 — 서버에 연결할 수 없어요');
    }

    if (res.status === 401) {
      // 토큰 만료/오류
      clearToken();
      showLogin('토큰이 유효하지 않아요. 다시 로그인해주세요.');
      throw new Error('Unauthorized');
    }
    if (res.status === 503) {
      throw new Error('어드민이 비활성 상태예요 (서버에 ADMIN_TOKEN 미설정)');
    }

    let data = null;
    try { data = await res.json(); } catch { /* no-op */ }
    if (!res.ok) {
      const msg = data?.error || `요청 실패 (${res.status})`;
      throw new Error(msg);
    }
    return data;
  }

  const apis = {
    health: () => api('GET', '/api/admin/health'),

    // 사용자
    listUsers: (q, blocked, limit, offset) => {
      const p = new URLSearchParams();
      if (q) p.set('q', q);
      if (blocked !== '') p.set('blocked', blocked);
      p.set('limit', limit ?? 50);
      p.set('offset', offset ?? 0);
      return api('GET', `/api/admin/users?${p}`);
    },
    getUser: (id) => api('GET', `/api/admin/users/${encodeURIComponent(id)}`),
    blockUser: (id, reason) => api('POST', `/api/admin/users/${encodeURIComponent(id)}/block`, { reason }),
    unblockUser: (id) => api('POST', `/api/admin/users/${encodeURIComponent(id)}/unblock`, {}),
    verifyUser: (id, level) => api('POST', `/api/admin/users/${encodeURIComponent(id)}/verify`, { level }),

    // 상품
    listProducts: (q, hidden, limit, offset) => {
      const p = new URLSearchParams();
      if (q) p.set('q', q);
      if (hidden !== '') p.set('hidden', hidden);
      p.set('limit', limit ?? 50);
      p.set('offset', offset ?? 0);
      return api('GET', `/api/admin/products?${p}`);
    },
    hideProduct: (id, reason) => api('POST', `/api/admin/products/${encodeURIComponent(id)}/hide`, { reason }),
    unhideProduct: (id) => api('POST', `/api/admin/products/${encodeURIComponent(id)}/unhide`, {}),
    deleteProduct: (id) => api('DELETE', `/api/admin/products/${encodeURIComponent(id)}`),

    // QKEY
    qkeyTransactions: (userId, limit, offset) => {
      const p = new URLSearchParams();
      if (userId) p.set('user_id', userId);
      p.set('limit', limit ?? 100);
      p.set('offset', offset ?? 0);
      return api('GET', `/api/admin/qkey/transactions?${p}`);
    },
    qkeyWithdrawals: (status, limit, offset) => {
      const p = new URLSearchParams();
      if (status) p.set('status', status);
      p.set('limit', limit ?? 100);
      p.set('offset', offset ?? 0);
      return api('GET', `/api/admin/qkey/withdrawals?${p}`);
    },

    // 통계
    statsOverview: () => api('GET', '/api/admin/stats/overview'),

    // 공지
    listNotices: (active) => {
      const p = new URLSearchParams();
      if (active !== '') p.set('active', active);
      return api('GET', `/api/admin/notices?${p}`);
    },
    createNotice: (payload) => api('POST', '/api/admin/notices', payload),
    deleteNotice: (id) => api('DELETE', `/api/admin/notices/${id}`),
    toggleNotice: (id) => api('POST', `/api/admin/notices/${id}/toggle`, {}),

    // 신고
    listReports: (status, limit, offset) => {
      const p = new URLSearchParams();
      p.set('status', status || 'pending');
      p.set('limit', limit ?? 100);
      p.set('offset', offset ?? 0);
      return api('GET', `/api/admin/reports?${p}`);
    },
    resolveReport: (id, note) => api('POST', `/api/admin/reports/${id}/resolve`, { note }),
    dismissReport: (id, note) => api('POST', `/api/admin/reports/${id}/dismiss`, { note }),

    // 감사 로그
    listAudit: (limit, offset) => {
      const p = new URLSearchParams();
      p.set('limit', limit ?? 100);
      p.set('offset', offset ?? 0);
      return api('GET', `/api/admin/audit?${p}`);
    },
  };

  // ────────────────────────────────────────────────────────
  // UI 헬퍼
  // ────────────────────────────────────────────────────────
  function $(id) { return document.getElementById(id); }
  function el(tag, attrs, ...children) {
    const e = document.createElement(tag);
    if (attrs) {
      for (const k in attrs) {
        if (k === 'class') e.className = attrs[k];
        else if (k === 'html') e.innerHTML = attrs[k];
        else if (k.startsWith('on') && typeof attrs[k] === 'function') {
          e.addEventListener(k.substring(2).toLowerCase(), attrs[k]);
        } else if (attrs[k] !== undefined && attrs[k] !== null) {
          e.setAttribute(k, attrs[k]);
        }
      }
    }
    for (const c of children) {
      if (c == null) continue;
      if (typeof c === 'string') e.appendChild(document.createTextNode(c));
      else e.appendChild(c);
    }
    return e;
  }

  function toast(msg, type) {
    const t = $('toast');
    t.textContent = msg;
    t.className = 'toast' + (type ? ' ' + type : '');
    setTimeout(() => t.classList.add('hidden'), 3000);
    setTimeout(() => t.classList.remove(type || ''), 3000);
    t.classList.remove('hidden');
  }

  function fmtDate(s) {
    if (!s) return '';
    try {
      const d = new Date(s.includes('T') ? s : s.replace(' ', 'T') + 'Z');
      return d.toLocaleString('ko-KR');
    } catch { return s; }
  }
  function fmtNum(n) {
    if (n == null) return '0';
    return Number(n).toLocaleString('ko-KR');
  }
  function shortId(id) {
    if (!id) return '';
    return id.length > 12 ? id.substring(0, 8) + '…' : id;
  }
  function escapeHtml(s) {
    if (s == null) return '';
    return String(s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  // ────────────────────────────────────────────────────────
  // 화면 전환
  // ────────────────────────────────────────────────────────
  function showLogin(errMsg) {
    $('loginView').classList.remove('hidden');
    $('appView').classList.add('hidden');
    if (errMsg) {
      const eb = $('loginError');
      eb.textContent = errMsg;
      eb.classList.remove('hidden');
    }
  }
  function showApp() {
    $('loginView').classList.add('hidden');
    $('appView').classList.remove('hidden');
    $('apiBase').textContent = API_BASE.replace(/^https?:\/\//, '');
  }

  // ────────────────────────────────────────────────────────
  // 라우터
  // ────────────────────────────────────────────────────────
  const ROUTES = {
    dashboard: { title: '대시보드', render: () => window.PageDashboard.render(ctx) },
    users: { title: '사용자 관리', render: () => window.PageUsers.render(ctx) },
    products: { title: '상품 관리', render: () => window.PageProducts.render(ctx) },
    qkey: { title: 'QKEY 거래 원장', render: () => window.PageQkey.render(ctx) },
    notices: { title: '공지/푸시 발송', render: () => window.PageNotices.render(ctx) },
    reports: { title: '신고 처리', render: () => window.PageReports.render(ctx) },
    audit: { title: '감사 로그', render: () => window.PageAudit.render(ctx) },
  };

  const ctx = { apis, el, $, toast, fmtDate, fmtNum, shortId, escapeHtml };

  function navigate() {
    const hash = location.hash.replace(/^#\/?/, '') || 'dashboard';
    const route = ROUTES[hash] || ROUTES.dashboard;

    // sidebar active
    document.querySelectorAll('.sidebar nav a').forEach((a) => {
      a.classList.toggle('active', a.dataset.route === hash);
    });

    $('pageTitle').textContent = route.title;
    $('pageRoot').innerHTML = '<div class="empty">로딩 중...</div>';
    state.currentRoute = hash;
    try {
      route.render();
    } catch (e) {
      $('pageRoot').innerHTML =
        `<div class="error-box">${escapeHtml(e.message || String(e))}</div>`;
    }
  }

  // ────────────────────────────────────────────────────────
  // 부팅
  // ────────────────────────────────────────────────────────
  async function boot() {
    if (!applyPCGuard()) return;
    window.addEventListener('resize', applyPCGuard);

    // 로그인 폼
    $('loginForm').addEventListener('submit', async (e) => {
      e.preventDefault();
      const tok = $('adminToken').value.trim();
      if (!tok) return;
      saveToken(tok);
      // 토큰 검증 (health ping)
      $('loginError').classList.add('hidden');
      try {
        await apis.health();
        showApp();
        navigate();
        startServerTimePing();
      } catch (e) {
        clearToken();
        const eb = $('loginError');
        eb.textContent = e.message || '인증 실패';
        eb.classList.remove('hidden');
      }
    });

    $('logoutBtn').addEventListener('click', () => {
      clearToken();
      showLogin();
    });

    window.addEventListener('hashchange', navigate);

    // 토큰 있으면 자동 검증
    loadToken();
    if (state.token) {
      try {
        await apis.health();
        showApp();
        navigate();
        startServerTimePing();
      } catch {
        clearToken();
        showLogin();
      }
    } else {
      showLogin();
    }
  }

  // 서버 시간/연결 상태 모니터링
  let pingTimer = null;
  function startServerTimePing() {
    if (pingTimer) clearInterval(pingTimer);
    const tick = async () => {
      try {
        const h = await apis.health();
        $('serverTime').textContent = h.server_time
          ? new Date(h.server_time).toLocaleTimeString('ko-KR')
          : '';
        $('pingBadge').className = 'badge ok';
      } catch {
        $('pingBadge').className = 'badge err';
      }
    };
    tick();
    pingTimer = setInterval(tick, 30000);
  }

  // 노출
  window.AdminApp = {
    boot,
    apis,
    ctx,
    state,
    el,
    $,
    toast,
    showLogin,
  };
})();
