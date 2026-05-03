/* ② 상품 관리 (목록/숨김/해제/삭제) */
(function () {
  let state = { q: '', hidden: '', limit: 50, offset: 0 };

  async function render(ctx) {
    const { apis, el, $, toast, fmtDate, fmtNum, shortId, escapeHtml } = ctx;
    const root = $('pageRoot');
    root.innerHTML = '';

    const toolbar = el('div', { class: 'toolbar' });
    const qInput = el('input', { type: 'text', placeholder: '상품명 검색', value: state.q });
    const hiddenSel = el('select', null,
      el('option', { value: '' }, '전체'),
      el('option', { value: '0' }, '공개만'),
      el('option', { value: '1' }, '숨김만'),
    );
    hiddenSel.value = state.hidden;
    const searchBtn = el('button', { class: 'btn btn-primary' }, '검색');
    searchBtn.addEventListener('click', async () => {
      state.q = qInput.value.trim();
      state.hidden = hiddenSel.value;
      state.offset = 0;
      await load();
    });
    qInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') searchBtn.click(); });
    toolbar.append(qInput, hiddenSel, searchBtn);
    root.appendChild(toolbar);

    const section = el('div', { class: 'section' });
    const tableWrap = el('div');
    section.appendChild(tableWrap);
    root.appendChild(section);

    async function load() {
      tableWrap.innerHTML = '<div class="empty">불러오는 중...</div>';
      let data;
      try {
        data = await apis.listProducts(state.q, state.hidden, state.limit, state.offset);
      } catch (e) {
        tableWrap.innerHTML = `<div class="error-box">${escapeHtml(e.message)}</div>`;
        return;
      }
      const items = data.items || [];
      if (items.length === 0) {
        tableWrap.innerHTML = '<div class="empty">상품이 없어요</div>';
        return;
      }
      const tbl = el('table', { class: 'tbl' });
      tbl.innerHTML = `<thead><tr>
        <th>상품 ID</th><th>제목</th><th>가격</th><th>QTA</th>
        <th>판매자</th><th>지역</th><th>상태</th><th>등록</th><th>액션</th>
      </tr></thead>`;
      const tb = el('tbody');
      for (const p of items) {
        const isHidden = p.hidden_by_admin == 1;
        const tag = isHidden
          ? '<span class="tag tag-blocked">관리자 숨김</span>'
          : `<span class="tag tag-active">${escapeHtml(p.status || '판매중')}</span>`;

        const tr = el('tr', null,
          el('td', { class: 'small muted', title: p.id }, shortId(p.id)),
          el('td', null, p.title || ''),
          el('td', null, fmtNum(p.price || 0) + '원'),
          el('td', null, fmtNum(p.qta_amount || 0)),
          el('td', null, p.seller_nickname || shortId(p.seller_id)),
          el('td', null, p.region || '-'),
          el('td', { html: tag }),
          el('td', { class: 'small muted' }, fmtDate(p.created_at)),
        );

        const actions = el('div', { class: 'actions' });
        if (isHidden) {
          const b = el('button', { class: 'btn btn-primary' }, '공개');
          b.addEventListener('click', async () => {
            if (!confirm(`"${p.title}" 을 다시 공개할까요?`)) return;
            try { await apis.unhideProduct(p.id); toast('공개 완료', 'success'); load(); }
            catch (e) { toast(e.message, 'error'); }
          });
          actions.appendChild(b);
        } else {
          const b = el('button', { class: 'btn btn-warn' }, '숨김');
          b.addEventListener('click', async () => {
            const reason = prompt(`"${p.title}" 숨김 사유를 입력해주세요`, '');
            if (reason === null) return;
            try { await apis.hideProduct(p.id, reason); toast('숨김 처리 완료', 'success'); load(); }
            catch (e) { toast(e.message, 'error'); }
          });
          actions.appendChild(b);
        }
        const d = el('button', { class: 'btn btn-danger' }, '삭제');
        d.addEventListener('click', async () => {
          if (!confirm(`"${p.title}" 을 영구 삭제할까요? 되돌릴 수 없어요.`)) return;
          try { await apis.deleteProduct(p.id); toast('삭제 완료', 'success'); load(); }
          catch (e) { toast(e.message, 'error'); }
        });
        actions.appendChild(d);

        tr.appendChild(el('td', null, actions));
        tb.appendChild(tr);
      }
      tbl.appendChild(tb);
      tableWrap.innerHTML = '';
      tableWrap.appendChild(tbl);

      const pager = el('div', { class: 'pager' });
      const prev = el('button', { class: 'btn' }, '◀ 이전');
      const next = el('button', { class: 'btn' }, '다음 ▶');
      prev.addEventListener('click', () => {
        if (state.offset > 0) { state.offset = Math.max(0, state.offset - state.limit); load(); }
      });
      next.addEventListener('click', () => {
        if ((data.items || []).length === state.limit) { state.offset += state.limit; load(); }
      });
      pager.append(prev, next, el('span', { class: 'muted small info' }, `offset ${state.offset} · limit ${state.limit}`));
      tableWrap.appendChild(pager);
    }

    await load();
  }
  window.PageProducts = { render };
})();
