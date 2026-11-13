'use strict';
// Presentation only: copy/download always use the original PowerShell string.
const BuilderCodeView=(()=>{
 const escape=s=>s.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const tokens=/(#[^\n]*|"(?:`.|[^"`])*"|'(?:''|[^'])*'|\[[A-Za-z][\w.\[\]]*\]|\$(?:[\w:]+)|-[A-Za-z][\w-]*|\b[A-Za-z]+-[A-Za-z][\w-]*\b|\b\d+(?:\.\d+)*\b)/g;
 function highlight(s){let out='',pos=0;for(const m of s.matchAll(tokens)){out+=escape(s.slice(pos,m.index));const t=m[0],kind=t[0]==='#'?'comment':/^["']/.test(t)?'string':t[0]==='$'?'variable':t[0]==='['?'type':t[0]==='-'?'parameter':/^\d/.test(t)?'number':'command';out+='<span class="ps-'+kind+'">'+escape(t)+'</span>';pos=m.index+t.length;}return out+escape(s.slice(pos));}
 function render(el,code){el.classList.add('ps-code');el.innerHTML=code.replace(/\r\n/g,'\n').replace(/\n$/,'').split('\n').map((line,i)=>'<span class="ps-line" data-line="'+(i+1)+'"><span class="ps-text">'+highlight(line)+'</span></span>').join('\n');}
 return {render};
})();
