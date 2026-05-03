/* ① 사용자 관리 (검색/차단/해제/검증) */
(function () {
  let state = { q: '', blocked: '', limit: 50, offset: 0 };

  async function render(ctx) {
    const { apis, el, $, toast, fmtDate, fmtNum, shortId, escapeHtml } = ctx;
    const root = $('pageRoot');
    root.innerHTML = '';

    const toolbar = el('div', { class: 'toolbar' });
    const qInput = el('input', { type: 'text', placeholder: '닉네임 또는 지갑주소 검색', value: state.q });
    const blockedSel = el('select', null,
      el('option', { value: '' }, '전체'),
      el('option', { value: '0' }, '활성만'),
      el('option', { value: '1' }, '차단된 사용자만'),
    );
    blockedSel.value = state.blocked;
    const searchBtn = el('button', { class: 'btn btn-primary' }, '검색');
    searchBtn.addEventListener('click', async () => {
      state.q = qInput.value.trim();
      state.blocked = blockedSel.value;
      state.offset = 0;
      await load();
    });
    qInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') searchBtn.click(); });
    toolbar.append(qInput, blockedSel, searchBtn);
    root.appendChild(toolbar);

    const section = el('div', { class: 'section' });
    const tableWrap = el('div', { id: 'usersTable' });
    section.appendChild(tableWrap);
    root.appendChild(section);

    async function load() {
      tableWrap.innerHTML = '<div class="empty">불러오는 중...</div>';
      let data;
      try {
        data = await apis.listUsers(state.q, state.blocked, state.limit, state.offset);
      } catch (e) {
        tableWrap.innerHTML = `<div class="error-box">${escapeHtml(e.message)}</div>`;
        return;
      }
      const items = data.items || [];
      if (items.length === 0) {
        tableWrap.innerHTML = '<div class="empty">사용자가 없어요</div>';
        return;
      }
      const tbl = el('table', { class: 'tbl' });
      tbl.innerHTML = `<thead><tr>
        <th>닉네임</th><th>지갑주소</th><th>지역</th><th>매너</th>
        <th>QTA</th><th>인증</th><th>상태</th><th>가입</th><th>액션</th>
      </tr></thead>`;
      const tb = el('tbody');
      for (const u of items) {
        const isBlocked = u.is_blocked == 1;
        const verifyTag = u.verification_level === 2 ? '계좌'
          : u.verification_level === 1 ? '본인' : '미인증';
        const statusTag = isBlocked
          ? '<span class="tag tag-blocked">차단</span>'
          : '<span class="tag tag-active">활성</span>';

        const tr = el('tr', null,
          el('td', null, u.nickname || ''),
          el('td', { class: 'small muted', title: u.wallet_address || '' }, shortId(u.wallet_address)),
          el('td', null, u.region || '-'),
          el('td', null, fmtNum(u.manner_score || 0)),
          el('td', null, fmtNum(u.qta_balance || 0)),
          el('td', null, verifyTag),
          el('td', { html: statusTag }),
          el('td', { class: 'small muted' }, fmtDate(u.created_at)),
        );

        const actions = el('div', { class: 'actions' });
        if (isBlocked) {
          const b = el('button', { class: 'btn btn-primary' }, '해제');
          b.addEventListener('click', async () => {
            if (!confirm(`${u.nickname} 차단을 해제할까요?`)) return;
            try { await apis.unblockUser(u.id); toast('해제 완료', 'success'); load(); }
            catch (e) { toast(e.message, 'error'); }
          });
          actions.appendChild(b);
        } else {
          const b = el('button', { class: 'btn btn-danger' }, '차단');
          b.addEventListener('click', async () => {
            const reason = prompt(`${u.nickname} 차단 사유를 입력해주세요`, '');
            if (reason === null) return;
            try { await apis.blockUser(u.id, reason); toast('차단 완료', 'success'); load(); }
            catch (e) { toast(e.message, 'error'); }
          });
          actions.appendChild(b);
        }
        const v = el('button', { class: 'btn' }, '검증변경');
        v.addEventListener('click', async () => {
          const lv = prompt(`인증 단계 변경 (현재=${u.verification_level})\n0=미인증, 1=본인인증, 2=계좌등록`,
                            String(u.verification_level));
          if (lv === null) return;
          try { await apis.verifyUser(u.id, Number(lv)); toast('변경 완료', 'success'); load(); }
          catch (e) { toast(e.message, 'error'); }
        });
        actions.appendChild(v);

        tr.appendChild(el('td', null, actions));
        tb.appendChild(tr);
      }
      tbl.appendChild(tb);
      tableWrap.innerHTML = '';
      tableWrap.appendChild(tbl);
      tableWrap.appendChild(pager(data, () => load()));
    }

    function pager(data, reload) {
      const wrap = el('div', { class: 'pager' });
      const prev = el('button', { class: 'btn' }, '◀ 이전');
      const next = el('button', { class: 'btn' }, '다음 ▶');
      prev.addEventListener('click', () => {
        if (state.offset > 0) { state.offset = Math.max(0, state.offset - state.limit); reload(); }
      });
      next.addEventListener('click', () => {
        if ((data.items || []).length === state.limit) { state.offset += state.limit; reload(); }
      });
      const info = el('span', { class: 'muted small info' }, `offset ${state.offset} · limit ${state.limit}`);
      wrap.append(prev, next, info);
      return wrap;
    }

    await load();
  }
  window.PageUsers = { render };
})();
