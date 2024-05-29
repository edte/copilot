scriptencoding utf-8

let g:copilot_setup_tip = "Gongfeng Copilot：You can setup with command:Copilot setup"
let g:copilot_login_tip = "Gongfeng Copilot：You can coding now!"

" 忽略的语言
function! copilot#lsp#GetFiletypeDefaults() abort
  let copilot_filetype_defaults = {
	\ 'gitcommit': 0,
	\ 'gitrebase': 0,
	\ 'hgcommit': 0,
	\ 'svn': 0,
	\ 'cvs': 0,
	\ '.': 0}
  return copilot_filetype_defaults
endfunction

" 部分采纳
function! copilot#lsp#AcceptCompletionPart() abort
  let accept_method = 'gongfeng-notify/accept-completion-line'
  call s:AcceptCompletion(accept_method)
endfunction

" 全采纳
function! copilot#lsp#AcceptCompletionAll() abort
  let accept_method = 'gongfeng-notify/accept-completion'
  call s:AcceptCompletion(accept_method)
endfunction

" 采纳
function! s:AcceptCompletion(accept_method) abort
  if (!exists('b:_copilot.suggestions') || !exists('b:_copilot.params'))
    return
  endif
  let choice = get(b:_copilot.suggestions, b:_copilot.choice, {})
  if has_key(choice, 'insertText')
    let choice.text = choice.insertText
    let params = {
      \ 'completionId': choice.id,
      \ 'snippet': choice.insertText,
      \ 'uri': b:_copilot.params.uri,
      \ 'position': choice.range.start,
      \ }
    let agent = copilot#Agent()
    call copilot#agent#WholeNotify(agent,a:accept_method,params)
  endif
endfunction

" 代码补全
function! copilot#lsp#Completion(params,...) abort
  let completion_method = 'gongfeng/stream-completions'
  return call('copilot#agent#WholeRequest', [completion_method, a:params] + a:000)
endfunction

" 主动更新配置信息
function! copilot#lsp#ConfigUpdate(agent,enable) abort
  let g:copilot_completion_enabled = a:enable
  let config_method = 'gongfeng/update-config'
  call copilot#agent#WholeRequest(config_method,copilot#lsp#GetUpdateConfig(), function('s:ConfigUpdateSuccess'),function('s:ConfigUpdateError'),a:agent)
endfunction

" 更新配置成功
function! s:ConfigUpdateSuccess(result, agent) abort
  "echom 'ConfigUpdateSuccess'
  "echom a:result
endfunction

" 更新配置成功
function! s:ConfigUpdateError(result, agent) abort
  "echom 'ConfigUpdateError'
  "echom a:result
endfunction

" 成功初始化
function! copilot#lsp#Initialized(agent,result) abort
  call copilot#logger#Info("[Response] " . json_encode(a:result))
	" 发送初始化成功的通知
  call copilot#agent#WholeNotify(a:agent,'initialized',{})
  " 读取缓存信息，开始登录
  call copilot#util#Defer({-> copilot#lsp#CheckConfig(a:agent)}) 
endfunction

" 获取设备码
function! copilot#lsp#GetDeviceCode(agent) abort
	let auth_method = 'gongfeng/oauth-device-code'
	let params = {
		\ 'force': v:true,
		\ }
  call copilot#agent#WholeRequest(auth_method, params, function('s:GetDeviceCodeSuccess'),function('s:GetDeviceCodeError'),a:agent)
endfunction

" 获取设备码失败
function! s:GetDeviceCodeError(result, agent) abort
  echo a:result
endfunction

" 获取设备码成功
function! s:GetDeviceCodeSuccess(result, agent) abort
  echo "First copy your one-time code: " . a:result.userCode . "\n" . "Visit " . a:result.verificationUri
	let auth_method = 'gongfeng/oauth-device-token'
	let params = {
		\ 'deviceCode': a:result.deviceCode,
		\ 'userCode': a:result.userCode,
    \ 'expiresAt': a:result.expiresAt,
    \ 'intervalMs': a:result.intervalMs,
		\ }
  call copilot#agent#WholeRequest(auth_method, params, function('s:GetTokenSuccess'),function('s:GetTokenError'),a:agent)
endfunction

" 获取token授权失败
function! s:GetTokenError(result, agent) abort
  echo a:result
endfunction

" 获取token授权成功
function! s:GetTokenSuccess(result, agent,...) abort
	let auth_method = 'gongfeng/authentication'
	let params = {
		\ 'token': a:result.accessToken,
		\ 'user': a:result.username,
		\ }
  let g:copilot_token = a:result.accessToken
  let g:copilot_user = a:result.username
  call copilot#agent#WholeRequest(auth_method, params, function('s:AuthSuccess'),function('s:AuthError'),a:agent,params)
endfunction

"授权失败
function! s:AuthError(result, agent,params) abort
  echo g:copilot_setup_tip
endfunction

" 授权成功
function! s:AuthSuccess(result, agent,params) abort
  echo g:copilot_login_tip
  let g:copilot_login = 1
  call copilot#lsp#ConfigUpdate(a:agent, g:copilot_completion_enabled)
endfunction

" 检测本地缓存，存在就登陆
function! copilot#lsp#CheckConfig(agent) abort
  let config_method = 'gongfeng/update-config'
  call copilot#agent#WholeRequest(config_method, copilot#lsp#GetUpdateConfig(), function('s:GetConfigSuccess'),function('s:GetConfigError'),a:agent)
endfunction

" 授权成功
function! s:GetConfigSuccess(result,agent) abort
  "echom "GetConfigSuccess"
  call copilot#logger#Debug(json_encode(a:result))
  if has_key(a:result, 'enableCompletions')
		let g:copilot_completion_enabled = empty(a:result.enableCompletions) ? 0 : 1
  else
    let g:copilot_completion_enabled = 1
	endif
  if (has_key(a:result, 'token') && has_key(a:result, 'user'))
    let g:copilot_token = a:result.token
    let g:copilot_user = a:result.user
		let auth_method = 'gongfeng/authentication'
    let params = {
      \ 'token': a:result.token,
      \ 'user': a:result.user,
      \ }
      call copilot#agent#WholeRequest(auth_method, params, function('s:AuthSuccess'),function('s:RefreshToken'),a:agent,params)
	else
    echo g:copilot_setup_tip
  endif
endfunction

" 登录失败，刷新token
function! s:GetConfigError(result,agent) abort
  "echom "GetConfigError"
  echo g:copilot_setup_tip
endfunction

function! s:CheckConfigHandle(channel, msg)
   "echom "CheckConfigHandle"
   "echom a:msg
endfunc

" 登录失败，刷新token
function! s:RefreshToken(result,agent,old_params) abort
	let refresh_auth_method = 'gongfeng/refresh-token'
	let params = {
		\ 'token': a:old_params.token,
		\ 'user': a:old_params.user,
		\ }
  call copilot#agent#WholeRequest(refresh_auth_method, params, function('s:GetTokenSuccess'),function('s:RefreshTokenError'),a:agent)
endfunction

" 刷新token失败
function! s:RefreshTokenError(result, agent) abort
  echo g:copilot_setup_tip
endfunction

" 生成配置信息
function! copilot#lsp#GetUpdateConfig() abort
	let filetypes = copy(copilot#lsp#GetFiletypeDefaults())
	if type(get(g:, 'copilot_filetypes')) == v:t_dict
			call extend(filetypes, g:copilot_filetypes)
	endif
	let editor_config = {
		\ 'disabledLanguages': map(sort(keys(filter(filetypes, { k, v -> empty(v) }))), { _, v -> {'languageId': v}}),
		\ }
	if exists('g:copilot_completion_enabled')
		let editor_config['enableCompletions'] = empty(g:copilot_completion_enabled) ? v:false : v:true
	endif
  if exists('g:copilot_token')
		let editor_config['token'] = g:copilot_token
	endif
  if exists('g:copilot_user')
		let editor_config['user'] = g:copilot_user
	endif
  if exists('g:copilot_log_file')
    let editor_config['logPath'] = g:copilot_log_file
  endif
	return editor_config
endfunction

" chmod +x 允许二进制
function! copilot#lsp#EnablePermission(lsp_file_path) abort
  let chmodCmd = 'chmod +x ' . a:lsp_file_path
  let out = []
  let err = []
  let status = copilot#job#Stream(chmodCmd, function('add', [out]), function('add', [err]))
  if status != 0
    let msg = 'chmod error:' . status . " file:" .lsp_file_path
    echoerr msg
    call copilot#logger#Error(msg)
  endif
endfunction
