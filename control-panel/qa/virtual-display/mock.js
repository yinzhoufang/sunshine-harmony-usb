// Test server only: never aliased in a production build.
let offline=false, id=1
const state={ protocol_version:1, vdd:{active:false,cooldown:false,awaiting_confirmation:false}, operation:{},sessions:[],status:'idle' }
export function scenario(value){if(value==='offline')offline=true;if(value==='online')offline=false;if(value==='stream')state.status='streaming';if(value==='confirm')state.vdd.awaiting_confirmation=false}
export async function invoke(command,args){
 if(command==='parse_sunshine_config')return {locale:'zh'}
 if(command==='get_vdd_status')return {state:'ready',running:true,installed:true,control_available:true,version_match:true}
 if(command==='get_gpus')return ['NVIDIA GeForce RTX 4060 Laptop GPU']
 if(command==='get_virtual_display_power'){if(offline)throw 'Request tray state failed: connection refused';return structuredClone(state)}
 if(command==='set_virtual_display_power'){
  if(state.status==='streaming'&&!args.enabled&&!args.allowInterrupt)throw 'VDD_STREAMING_CONFIRM_REQUIRED'
  const operation_id=++id;state.operation={id:operation_id,action:args.enabled?'vdd_create':'vdd_destroy',state:'running'};state.vdd.cooldown=true
  setTimeout(()=>{state.vdd.active=args.enabled;state.vdd.awaiting_confirmation=args.enabled;state.operation.state='succeeded';state.vdd.cooldown=false},600)
  return {status:true,operation_id,tray_state:structuredClone(state)}
 }
 if(command==='get_proxy_url')return 'http://127.0.0.1:5190'
 return {}
}
export async function listen(){return ()=>{}}
export async function emit(){}
