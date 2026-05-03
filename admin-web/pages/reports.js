/* ⑥ 신고 처리 */
(function () {
  let state = { status: 'pending', limit: 100, offset: 0 };

  async function render(ctx) {
    const { apis, el, $, toast, fmtDate, shortId, escapeHtml } = ctx;
    const root = $('pageRoot');
    root.innerHTML = '';

    const toolbar = el('div', { class: 'toolbar' });
    const sel = el('select', null,
      el('option', { value: 'pending' }, '대기 중'),
      el('option', { value: 'resolved' }, '처리 완료'),
      el('option', { value: 'dismissed' }, '기각됨'),
    );
    sel.value = state.status;
    sel.addEventListener('change', () => { state.status = sel.value; state.offset = 0; load(); });
    toolbar.append(el('label', null, '상태:'), sel);
    root.appendChild(toolbar);

    const sec = el('div', { class: 'section' });
    const tableWrap = el('div');
    sec.appendChild(tableWrap);
    root.appendChild(sec);

    async function load() {
      tableWrap.innerHTML = '<div class="empty">불러오는 중...</div>';
      let data;
      try { data = await apis.listReports(state.status, state.limit, state.offset); }
      catch (e) {
        tableWrap.innerHTML = `<div class="error-box">${escapeHtml(e.message)}</div>`;
        return;
      }
      const items = data.items || [];
      if (items.length === 0) {
        tableWrap.innerHTML = '<div class="empty">신고 없음</div>';
        return;
      }
      const tbl = el('table', { class: 'tbl' });
      tbl.innerHTML = `<thead><tr>
        <th>일시</th><th>신고자</th><th>피신고자</th><th>사유</th>
        <th>상세</th><th>상품</th><th>상태</th><th>액션</th>
      </tr></thead>`;
      const tb = el('tbody');
      for (const r of items) {
        let statusTag = '';
        if (r.status === 'pending') statusTag = '<span class="tag tag-pending">대기</span>';
        else if (r.status === 'resolved') statusTag = '<span class="tag tag-resolved">처리</span>';
        else statusTag = '<span class="tag tag-dismissed">기각</span>';

        const tr = el('tr', null,
          el('td', { class: 'small muted' }, fmtDate(r.created_at)),
          el('td', null, r.reporter_nickname || shortId(r.reporter_id)),
          el('td', null, r.reported_nickname || shortId(r.reported_id)),
          el('td', null, reasonLabel(r.reason)),
          el('td', { class: 'small muted', style: 'max-width:240px' }, r.detail || '-'),
          el('td', { class: 'small muted' }, r.product_id ? shortId(r.product_id) : '-'),
          el('td', { html: statusTag }),
        );
        const actions = el('div', { class: 'actions' });
        if (r.status === 'pending') {
          const ok = el('button', { class: 'btn btn-primary' }, '처리');
          ok.addEventListener('click', async () => {
            const note = prompt('처리 메모(옵션)', '');
            if (note === null) return;
            try { await apis.resolveReport(r.id, note); toast('처리 완료', 'success'); load(); }
            catch (e) { toast(e.message, 'error'); }
          });
          const dm = el('button', { class: 'btn' }, '기각');
          dm.addEventListener('click', async () => {
            const note = prompt('기각 사유(옵션)', '');
            if (note === null) return;
            try { await apis.dismissReport(r.id, note); toast('기각 처리 완료', 'success'); load(); }
            catch (e) { toast(e.message, 'error'); }
          });
          actions.append(ok, dm);
        } else {
          actions.appendChild(el('span', { class: 'small muted' },
            r.resolved_note ? escapeHtml(r.resolved_note) : ''));
        }
        tr.appendChild(el('td', null, actions));
        tb.appendChild(tr);
      }
      tbl.appendChild(tb);
      tableWrap.innerHTML = '';
      tableWrap.appendChild(tbl);
    }

    function reasonLabel(r) {
      const m = {
        spam: '스팸', fraud: '사기', abuse: '욕설/괴롭힘',
        inappropriate: '부적절', fake: '허위/가짜', other: '기타',
      };
      return m[r] || (r || '');
    }

    await load();
  }
  window.PageReports = { render };
})();
