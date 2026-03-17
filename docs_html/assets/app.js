/* syncitron Docs — Shared JavaScript */

// --- Dark mode ---
(function(){
  const key='syncitron-dark';
  const saved=localStorage.getItem(key);
  if(saved==='true') document.body.classList.add('dark');

  window.toggleDark=function(){
    document.body.classList.toggle('dark');
    localStorage.setItem(key,document.body.classList.contains('dark'));
    const btn=document.getElementById('theme-btn');
    if(btn) btn.textContent=document.body.classList.contains('dark')?'☀️ Light':'🌙 Dark';
  };

  document.addEventListener('DOMContentLoaded',()=>{
    const btn=document.getElementById('theme-btn');
    if(btn) btn.textContent=document.body.classList.contains('dark')?'☀️ Light':'🌙 Dark';
  });
})();

// --- Mobile sidebar toggle ---
window.toggleSidebar=function(){
  document.querySelector('.sidebar')?.classList.toggle('open');
};

// Close sidebar on content click (mobile)
document.addEventListener('click',e=>{
  const sb=document.querySelector('.sidebar');
  if(sb && sb.classList.contains('open') && !sb.contains(e.target) && !e.target.closest('.hamburger')){
    sb.classList.remove('open');
  }
});

// --- Mark active sidebar link ---
document.addEventListener('DOMContentLoaded',()=>{
  const current=location.pathname.split('/').pop()||'index.html';
  document.querySelectorAll('.sidebar a').forEach(a=>{
    const href=(a.getAttribute('href')||'').split('/').pop();
    if(href===current) a.classList.add('active');
  });
});
