/* 감사 로그 — 모든 어드민 액션 기록 */
(function () {
  async function render(ctx) {
    const { apis, el, $, fmtDate, shortId, escapeHtml } = ctx;
    const root = $('pageRoot');
    root.innerHTML = '<div class="empty">불러오는 중...</div>';

    let data;
    try { data = await apis.listAudit(100, 0); }
    catch (e) {
      root.innerHTML = `<div class="error-box">${escapeHtml(e.message)}</div>`;
      return;
    }
    const items = data.items || [];
    root.innerHTML = '';

    const sec = el('div', { class: 'section' });
    sec.appendChild(el('h3', null, `감사 로그 (최근 ${items.length}건)`));

    if (items.length === 0) {
      sec.appendChild(el('div', { class: 'empty' }, '기록 없음'));
      root.appendChild(sec);
      return;
    }

    const tbl = el('table', { class: 'tbl' });
    tbl.innerHTML = `<thead><tr>
      <th>일시</th><th>액션</th><th>대상</th><th>페이로드</th><th>IP</th>
    </tr></thead>`;
    const tb = el('tbody');
    for (const a of items) {
      let payload = a.payload_json;
      try { payload = JSON.stringify(JSON.parse(a.payload_json), null, 0); } catch {}
      const tr = el('tr', null,
        el('td', { class: 'small muted' }, fmtDate(a.created_at)),
        el('td', null, el('span', { class: 'tag tag-active' }, a.action || '')),
        el('td', { class: 'small muted', title: a.target_id || '' }, shortId(a.target_id)),
        el('td', { class: 'small', style: 'max-width:400px;font-family:ui-monospace,monospace;word-break:break-all' },
          (payload || '').substring(0, 200)),
        el('td', { class: 'small muted' }, a.ip || ''),
      );
      tb.appendChild(tr);
    }
    tbl.appendChild(tb);
    sec.appendChild(tbl);
    root.appendChild(sec);
  }
  window.PageAudit = { render };
})();
