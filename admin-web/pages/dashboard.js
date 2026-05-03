/* ④ 매출/통계 대시보드 */
(function () {
  async function render(ctx) {
    const { apis, el, $, fmtNum, escapeHtml } = ctx;
    const root = $('pageRoot');
    root.innerHTML = '<div class="empty">불러오는 중...</div>';

    let data;
    try {
      data = await apis.statsOverview();
    } catch (e) {
      root.innerHTML = `<div class="error-box">${escapeHtml(e.message)}</div>`;
      return;
    }
    const t = data.totals || {};

    const kpi = el('div', { class: 'kpi-grid' },
      kpiCard('총 사용자', t.users, ''),
      kpiCard('총 상품', t.products, ''),
      kpiCard('차단 사용자', t.blocked_users, t.blocked_users > 0 ? 'danger' : ''),
      kpiCard('숨김 상품', t.hidden_products, t.hidden_products > 0 ? 'warning' : ''),
      kpiCard('대기 신고', t.pending_reports, t.pending_reports > 0 ? 'warning' : ''),
    );

    const sec1 = el('div', { class: 'section' },
      el('h3', null, '최근 7일 가입자'),
      sparkline(data.recent_users_7d || []),
      tableForSeries(data.recent_users_7d || []),
    );
    const sec2 = el('div', { class: 'section' },
      el('h3', null, '최근 7일 상품 등록'),
      sparkline(data.recent_products_7d || []),
      tableForSeries(data.recent_products_7d || []),
    );

    root.innerHTML = '';
    root.appendChild(kpi);
    root.appendChild(sec1);
    root.appendChild(sec2);

    function kpiCard(label, value, cls) {
      return el('div', { class: 'kpi-card ' + (cls || '') },
        el('div', { class: 'label' }, label),
        el('div', { class: 'value' }, fmtNum(value || 0)),
      );
    }
    function sparkline(series) {
      if (!series || series.length === 0) {
        return el('div', { class: 'empty', style: 'padding:16px' }, '데이터 없음');
      }
      const max = Math.max(...series.map((r) => Number(r.n) || 0), 1);
      const wrap = el('div', { class: 'sparkline' });
      // 최근 7일 → 시계열 좌→우 (서버는 DESC 라 reverse)
      const seq = series.slice().reverse();
      for (const r of seq) {
        const h = Math.max(2, Math.round((Number(r.n) / max) * 60));
        const bar = el('div', { class: 'bar', title: `${r.day}: ${r.n}` });
        bar.style.height = h + 'px';
        wrap.appendChild(bar);
      }
      return wrap;
    }
    function tableForSeries(series) {
      const tbl = el('table', { class: 'tbl' });
      tbl.innerHTML = '<thead><tr><th>날짜</th><th style="text-align:right">건수</th></tr></thead>';
      const tb = el('tbody');
      const seq = series.slice().reverse();
      if (seq.length === 0) {
        tb.innerHTML = '<tr><td colspan="2" class="empty">데이터 없음</td></tr>';
      }
      for (const r of seq) {
        const tr = el('tr', null,
          el('td', null, r.day || ''),
          el('td', { style: 'text-align:right' }, fmtNum(r.n)),
        );
        tb.appendChild(tr);
      }
      tbl.appendChild(tb);
      return tbl;
    }
  }
  window.PageDashboard = { render };
})();
