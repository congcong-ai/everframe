'use strict';
let token = localStorage.getItem('session') || '';
let polling = false;
const $ = id => document.getElementById(id);
const notice = text => { $('notice').textContent = text; };
function paired(value) { $('pair').hidden = value; $('control').hidden = !value; }
async function api(path, body) {
  const response = await fetch(path, {method:body === undefined?'GET':'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(8000)});
  const result = await response.json();
  if(response.status===401){token='';localStorage.removeItem('session');paired(false);}
  if(!response.ok) throw new Error(result.error || '请求失败');
  return result;
}
const duration = seconds => `${Math.floor(seconds/3600)}小时${Math.floor(seconds%3600/60)}分钟`;
const clock = date => new Date(date).toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit'});
const gb = bytes => `${(bytes/1e9).toFixed(1)} GB`;
function row(title, detail) { const div=document.createElement('div');div.className='row';const h=document.createElement('h3');h.textContent=title;const p=document.createElement('p');p.textContent=detail;div.append(h,p);return div; }
async function refresh(){
  if(!token || polling) return; polling=true;
  try{
    const s=await api('/api/status'); paired(true);$('name').textContent=s.name;document.title=s.name;
    $('recording').textContent=s.recording?'● REC · 正在记录':'尚未记录';$('elapsed').textContent=duration(s.elapsed);$('today').textContent=duration(s.todaySeconds);$('used').textContent=gb(s.usedBytes);$('free').textContent=gb(s.freeBytes);$('ai').textContent=s.ai;
    $('start').disabled=s.recording||s.busy;$('stop').disabled=!s.recording||s.busy;
    const timeline=await api('/api/timeline');$('timeline').replaceChildren(...timeline.map(e=>row(`${clock(e.startAt)}–${clock(e.endAt)} ${e.importance>=75?'⭐ '+e.importance:''} ${e.title}`,e.summary)));
    if(!timeline.length)$('timeline').textContent='还没有整理好的时间轴。可在手机设置启用 AI。';
    const clips=await api('/api/clips');$('clips').replaceChildren(...clips.map(c=>{
      const div=row(`${clock(c.startAt)} · ${duration(c.duration)} · ${gb(c.fileSize)} ${c.locked||c.pendingLock?'⭐ 已保留':''}`,c.summary||`AI：${({pending:'等待',running:'处理中',completed:'已整理',failed:'失败，可在手机重试'})[c.aiStatus]||c.aiStatus}`);
      const button=document.createElement('button');button.textContent=c.locked||c.pendingLock?'取消保留':'保留';button.onclick=()=>act(`/api/clips/${c.id}/${c.locked||c.pendingLock?'unlock':'lock'}`);div.append(button);return div;
    }));
    const summary=await api('/api/daily-summary');$('summary').replaceChildren();if(summary)$('summary').append(row('今日总结',summary.summary),row('主要完成',summary.accomplishments.join('；')),row('重要想法',summary.ideas.join('；')));
  }catch(error){notice(error.message||'连接中断，请检查手机是否保持前台');}finally{polling=false;}
}
async function act(path,body={}){try{await api(path,body);notice('操作已接收');await refresh();}catch(e){notice(e.message);}}
$('pair-form').onsubmit=async event=>{event.preventDefault();try{const result=await api('/api/pair',{code:$('code').value});token=result.token;localStorage.setItem('session',token);$('code').value='';notice('已配对，保持手机前台。');await refresh();}catch(e){notice(e.message);}};
$('start').onclick=()=>act('/api/start');$('stop').onclick=()=>act('/api/stop');document.querySelectorAll('[data-keep]').forEach(button=>button.onclick=()=>act('/api/keep',{minutes:Number(button.dataset.keep)}));$('daily').onclick=()=>act('/api/daily-summary');$('logout').onclick=()=>{token='';localStorage.removeItem('session');paired(false);};paired(Boolean(token));refresh();setInterval(refresh,5000);
