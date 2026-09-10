<script nonce="@@NONCE@@">
(function(){
var box=document.createElement('div');
box.style.cssText='position:fixed;left:0;bottom:0;right:0;z-index:2147483647;background:#8b1a1a;color:#fff;font:11px/1.4 monospace;padding:4px 8px;white-space:pre-wrap;word-break:break-all;pointer-events:none';
(document.body||document.documentElement).appendChild(box);
var logs=[];
function L(m){logs.push(m);if(logs.length>8)logs.shift();box.textContent=logs.join(' | ')}
L('__dbg_boot HTML_OK');
try{L('vscodeApi='+(typeof acquireVsCodeApi!=='undefined'?'1':'0'))}catch(e){L('api_chk_err')}
window.addEventListener('error',function(ev){L('JSERR: '+(ev.message||'').slice(0,140))});
window.addEventListener('message',function(e){
var d=e.data;
if(!d)return;
if(d.grpc_response){
if(d.grpc_response.error){L('GRPC_ERR: '+String(d.grpc_response.error).slice(0,140))}
else{var m=d.grpc_response.message;var st=(m&&m.stateJson)?(' state='+String(m.stateJson).slice(0,50)):(m?(' '+Object.keys(m).slice(0,4).join(',')):'');L('GRPC_OK id='+d.grpc_response.request_id+st)}
}
if(d.type==='state'){L('STATE_MSG')}
});
var rn=-1;
setInterval(function(){
var c=document.getElementById('root');
var k=c?c.childElementCount:-1;
if(k!==rn){rn=k;L('root_children='+k)}
},400);
setTimeout(function(){L('t+5s')},5000);
})();
</script>
