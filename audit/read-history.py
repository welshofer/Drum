"""Read selected transcript records without writing raw transcript content."""
import json,re,sys
from pathlib import Path
items=[h for h in json.loads(Path('audit/history-index.json').read_text()) if not h['current_audit']]
idx=int(sys.argv[1]); lo=int(sys.argv[2]); hi=int(sys.argv[3]); mode=sys.argv[4] if len(sys.argv)>4 else 'messages'
p=Path(items[idx]['path']); counts={}
def unpack(v):
 if isinstance(v,list): return "\n".join(unpack(x) for x in v)
 if isinstance(v,dict):
  for k in ['output','text','value','content']:
   if k in v: return unpack(v[k])
  return ''
 if isinstance(v,str):
  try: return unpack(json.loads(v))
  except (ValueError,TypeError): return v
 return ''
def scrub(s):
 s=re.sub(r'(?:sk-[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9_]+|AIza[A-Za-z0-9_-]+)', '[REDACTED]',s)
 s=re.sub(r'(?i)(authorization|api[_-]?key|access[_-]?token|refresh[_-]?token|password|secret)\s*[:=]\s*["\']?[^\s,"\'}]+',r'\1=[REDACTED]',s)
 return s
for n,line in enumerate(p.open(),1):
 if not lo<=n<=hi: continue
 o=json.loads(line); t=o.get('type'); q=o.get('payload',{}) if t=='response_item' else o.get('message',{})
 text=''; kind=''
 if t in ['assistant','user'] or (t=='response_item' and q.get('type')=='message'):
  c=q.get('content',[]); role=q.get('role',t)
  if isinstance(c,str): text=c
  else: text='\n'.join(x.get('text','') for x in c if isinstance(x,dict) and x.get('type') in ['text','output_text','input_text'])
  kind=role
  if '<environment_context>' in text or 'skills_instructions' in text: text='[injected instructions omitted]'
  if mode!='messages': text=''
 if mode in ['tools','results']:
  if t=='response_item' and q.get('type') in ['function_call','custom_tool_call']:
   kind=q.get('name'); text=str(q.get('arguments',q.get('input','')))
  elif t=='response_item' and q.get('type') in ['function_call_output','custom_tool_call_output']:
   kind='result'; text=unpack(q.get('output',''))
  elif t=='user':
   c=q.get('content',[])
   if isinstance(c,list):
    kind='result'; text='\n'.join(str(x.get('content','')) for x in c if isinstance(x,dict) and x.get('type')=='tool_result')
  elif t=='assistant':
   c=q.get('content',[])
   if isinstance(c,list):
    kind='call'; text='\n'.join(str(x.get('name',''))+' '+str(x.get('input','')) for x in c if isinstance(x,dict) and x.get('type')=='tool_use')
  if mode=='results' and kind!='result': text=''
  # Only print relevant error/verification/procedural snippets, not raw environment/UI/image data.
  if text:
   parts=text.splitlines(); matched=[]
   for j,s in enumerate(parts):
    if re.search(r'error:|warning:|failed|FAIL|SUCCEEDED|BUILD |TEST |permission|denied|killall|pkill|preview|BUILD_DIR|derive|Toolchain|CodeSign|resource.fork|[0-9]+ tests|xcodebuild|xcodegen|notify-tracing|Starting recording|Trace file had no',s,re.I): matched.append(s[:350])
   text='\n'.join(matched[:5])
 if text.strip():
  print(f'[{n}] {o.get("timestamp", "")} {kind}: {scrub(text[:4000])}')
