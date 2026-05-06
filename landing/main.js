/* ====================================================================
   Eggplant 🍆 Landing — main.js
   - 모바일 햄버거 메뉴 토글
   - 스크롤 시 nav 그림자/border 활성화
   - 앵커 링크 부드러운 스크롤 (Safari 보강)
   ==================================================================== */
(() => {
  'use strict';

  const nav     = document.getElementById('nav');
  const burger  = document.getElementById('burger');
  const drawer  = document.getElementById('drawer');

  // ---- 햄버거 메뉴 ----
  if (burger && drawer) {
    burger.addEventListener('click', () => {
      const open = burger.getAttribute('aria-expanded') === 'true';
      burger.setAttribute('aria-expanded', String(!open));
      if (open) {
        drawer.setAttribute('hidden', '');
      } else {
        drawer.removeAttribute('hidden');
      }
    });

    // 드로어 안의 링크 클릭 시 자동 닫기.
    drawer.querySelectorAll('a').forEach((a) => {
      a.addEventListener('click', () => {
        burger.setAttribute('aria-expanded', 'false');
        drawer.setAttribute('hidden', '');
      });
    });
  }

  // ---- 스크롤 시 nav scrolled 클래스 ----
  let ticking = false;
  const onScroll = () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => {
      if (nav) {
        if (window.scrollY > 8) nav.classList.add('scrolled');
        else nav.classList.remove('scrolled');
      }
      ticking = false;
    });
  };
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  // ---- 앵커 부드러운 스크롤 (Safari 구버전 fallback) ----
  document.querySelectorAll('a[href^="#"]').forEach((a) => {
    a.addEventListener('click', (e) => {
      const id = a.getAttribute('href');
      if (!id || id === '#') return;
      const tgt = document.querySelector(id);
      if (!tgt) return;
      e.preventDefault();
      const navH = nav ? nav.offsetHeight : 0;
      const top  = tgt.getBoundingClientRect().top + window.scrollY - navH - 8;
      window.scrollTo({ top, behavior: 'smooth' });
    });
  });

  // ---- IntersectionObserver: 섹션 페이드인 ----
  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((en) => {
        if (en.isIntersecting) {
          en.target.classList.add('in-view');
          io.unobserve(en.target);
        }
      });
    }, { threshold: 0.12 });
    document.querySelectorAll('.feature, .trust-card, .steps li, .qta-card, .dl-card')
      .forEach((el) => io.observe(el));
  }
})();
