/* ⑤ 공지/푸시 발송 */
(function () {
  async function render(ctx) {
    const { apis, el, $, toast, fmtDate, escapeHtml } = ctx;
    const root = $('pageRoot');
    root.innerHTML = '';

    // 발송 폼
    const form = el('div', { class: 'section' });
    form.appendChild(el('h3', null, '신규 발송'));
    const typeSel = el('select', null,
      el('option', { value: 'notice' }, '앱 내 공지'),
      el('option', { value: 'push' }, '푸시 알림'),
      el('option', { value: 'banner' }, '메인 배너'),
    );
    const targetSel = el('select', null,
      el('option', { value: 'all' }, '전체'),
      el('option', { value: 'region' }, '특정 지역'),
      el('option', { value: 'user' }, '특정 사용자'),
    );
    const targetVal = el('input', { type: 'text', placeholder: '지역명 또는 user_id (target=all 인 경우 비워두세요)' });
    const titleIn = el('input', { type: 'text', placeholder: '제목 (필수)', maxlength: 100 });
    const bodyIn = el('textarea', { placeholder: '본문 (선택)' });
    const linkIn = el('input', { type: 'text', placeholder: '링크 URL (선택)' });
    const startsIn = el('input', { type: 'datetime-local', placeholder: '시작' });
    const endsIn = el('input', { type: 'datetime-local', placeholder: '종료' });
    const submitBtn = el('button', { class: 'btn btn-primary' }, '발송');

    form.append(
      row('종류', typeSel),
      row('대상', targetSel),
      row('대상 값', targetVal),
      row('제목', titleIn),
      row('본문', bodyIn),
      row('링크', linkIn),
      row('시작', startsIn),
      row('종료', endsIn),
      row('', submitBtn),
    );
    root.appendChild(form);

    // 목록
    const listSec = el('div', { class: 'section' });
    listSec.appendChild(el('h3', null, '발송 내역'));
    const listWrap = el('div');
    listSec.appendChild(listWrap);
    root.appendChild(listSec);

    submitBtn.addEventListener('click', async () => {
      const title = titleIn.value.trim();
      if (!title) { toast('제목을 입력해주세요', 'error'); return; }
      try {
        await apis.createNotice({
          type: typeSel.value,
          target: targetSel.value,
          target_value: targetVal.value.trim() || null,
          title,
          body: bodyIn.value,
          link_url: linkIn.value.trim() || null,
          starts_at: startsIn.value ? startsIn.value.replace('T', ' ') + ':00' : null,
          ends_at: endsIn.value ? endsIn.value.replace('T', ' ') + ':00' : null,
        });
        toast('발송 등록 완료', 'success');
        titleIn.value = ''; bodyIn.value = ''; linkIn.value = ''; targetVal.value = '';
        load();
      } catch (e) {
        toast(e.message, 'error');
      }
    });

    async function load() {
      listWrap.innerHTML = '<div class="empty">불러오는 중...</div>';
      let data;
      try { data = await apis.listNotices(''); }
      catch (e) {
        listWrap.innerHTML = `<div class="error-box">${escapeHtml(e.message)}</div>`;
        return;
      }
      const items = data.items || [];
      if (items.length === 0) {
        listWrap.innerHTML = '<div class="empty">발송 내역 없음</div>';
        return;
      }
      const tbl = el('table', { class: 'tbl' });
      tbl.innerHTML = `<thead><tr>
        <th>종류</th><th>대상</th><th>제목</th><th>본문</th>
        <th>활성</th><th>발송일</th><th>액션</th>
      </tr></thead>`;
      const tb = el('tbody');
      for (const n of items) {
        const active = n.active == 1;
        const tag = active
          ? '<span class="tag tag-active">활성</span>'
          : '<span class="tag tag-dismissed">비활성</span>';
        const tr = el('tr', null,
          el('td', null, n.type),
          el('td', null, n.target + (n.target_value ? `(${escapeHtml(n.target_value)})` : '')),
          el('td', null, n.title),
          el('td', { class: 'small muted', style: 'max-width:300px' }, (n.body || '').substring(0, 80)),
          el('td', { html: tag }),
          el('td', { class: 'small muted' }, fmtDate(n.created_at)),
        );
        const actions = el('div', { class: 'actions' });
        const t = el('button', { class: 'btn' }, active ? '비활성화' : '활성화');
        t.addEventListener('click', async () => {
          try { await apis.toggleNotice(n.id); toast('변경 완료', 'success'); load(); }
          catch (e) { toast(e.message, 'error'); }
        });
        const d = el('button', { class: 'btn btn-danger' }, '삭제');
        d.addEventListener('click', async () => {
          if (!confirm('이 공지를 삭제할까요?')) return;
          try { await apis.deleteNotice(n.id); toast('삭제 완료', 'success'); load(); }
          catch (e) { toast(e.message, 'error'); }
        });
        actions.append(t, d);
        tr.appendChild(el('td', null, actions));
        tb.appendChild(tr);
      }
      tbl.appendChild(tb);
      listWrap.innerHTML = '';
      listWrap.appendChild(tbl);
    }

    function row(label, control) {
      return el('div', { class: 'form-row' },
        el('label', null, label),
        control,
      );
    }

    await load();
  }
  window.PageNotices = { render };
})();
