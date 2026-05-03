/* ③ QKEY 거래 원장 조회 (read-only) */
(function () {
  async function render(ctx) {
    const { apis, el, $, fmtDate, fmtNum, shortId, escapeHtml } = ctx;
    const root = $('pageRoot');
    root.innerHTML = '';

    // 탭: 거래내역 / 출금요청
    const tabs = el('div', { class: 'toolbar' });
    const tabTx = el('button', { class: 'btn btn-primary' }, '거래 내역');
    const tabWd = el('button', { class: 'btn' }, '출금 요청');
    tabs.append(tabTx, tabWd);
    root.appendChild(tabs);

    const userSearchRow = el('div', { class: 'toolbar' });
    const userIdIn = el('input', { type: 'text', placeholder: 'user_id (옵션) — 특정 사용자 거래만' });
    const reload = el('button', { class: 'btn' }, '조회');
    userSearchRow.append(userIdIn, reload);
    root.appendChild(userSearchRow);

    const sec = el('div', { class: 'section' });
    const tableWrap = el('div');
    sec.appendChild(tableWrap);
    root.appendChild(sec);

    let mode = 'tx';
    tabTx.addEventListener('click', () => { mode = 'tx'; tabTx.classList.add('btn-primary'); tabWd.classList.remove('btn-primary'); load(); });
    tabWd.addEventListener('click', () => { mode = 'wd'; tabWd.classList.add('btn-primary'); tabTx.classList.remove('btn-primary'); load(); });
    reload.addEventListener('click', () => load());

    async function load() {
      tableWrap.innerHTML = '<div class="empty">불러오는 중...</div>';
      try {
        if (mode === 'tx') {
          const data = await apis.qkeyTransactions(userIdIn.value.trim() || null, 100, 0);
          renderTx(data);
        } else {
          const data = await apis.qkeyWithdrawals('', 100, 0);
          renderWd(data);
        }
      } catch (e) {
        tableWrap.innerHTML = `<div class="error-box">${escapeHtml(e.message)}</div>`;
      }
    }

    function renderTx(data) {
      const items = data.items || [];
      if (items.length === 0) {
        tableWrap.innerHTML = `<div class="empty">${data.note ? escapeHtml(data.note) : '거래 내역 없음'}</div>`;
        return;
      }
      const tbl = el('table', { class: 'tbl' });
      // 컬럼은 qta_transactions 스키마에 의존 — 동적으로 첫 행 키를 헤더로
      const cols = Object.keys(items[0]);
      tbl.innerHTML = '<thead><tr>' +
        cols.map((c) => `<th>${escapeHtml(c)}</th>`).join('') +
        '</tr></thead>';
      const tb = el('tbody');
      for (const r of items) {
        const tr = el('tr');
        for (const c of cols) {
          let v = r[c];
          if (c.endsWith('_at') || c === 'created_at' || c === 'updated_at') v = fmtDate(v);
          else if (typeof v === 'number') v = fmtNum(v);
          else if (typeof v === 'string' && v.length > 20 && c.endsWith('_id')) v = shortId(v);
          tr.appendChild(el('td', { class: typeof r[c] === 'number' ? '' : 'small' }, v == null ? '' : String(v)));
        }
        tb.appendChild(tr);
      }
      tbl.appendChild(tb);
      tableWrap.innerHTML = '';
      tableWrap.appendChild(tbl);
    }

    function renderWd(data) {
      const items = data.items || [];
      if (items.length === 0) {
        tableWrap.innerHTML = `<div class="empty">${data.note ? escapeHtml(data.note) : '출금 요청 없음'}</div>`;
        return;
      }
      const tbl = el('table', { class: 'tbl' });
      tbl.innerHTML = `<thead><tr>
        <th>ID</th><th>닉네임</th><th>금액</th><th>상태</th><th>요청일</th>
      </tr></thead>`;
      const tb = el('tbody');
      for (const w of items) {
        const tr = el('tr', null,
          el('td', { class: 'small muted' }, shortId(String(w.id))),
          el('td', null, w.nickname || shortId(w.user_id)),
          el('td', null, fmtNum(w.amount || 0)),
          el('td', null, w.status || ''),
          el('td', { class: 'small muted' }, fmtDate(w.created_at)),
        );
        tb.appendChild(tr);
      }
      tbl.appendChild(tb);
      tableWrap.innerHTML = '';
      tableWrap.appendChild(tbl);
    }

    await load();
  }
  window.PageQkey = { render };
})();
