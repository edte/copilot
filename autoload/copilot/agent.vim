scriptencoding utf-8

let s:plugin_version = copilot#version#String()

let s:ide_version = v:version

let s:error_exit = -1

let s:root = expand('<sfile>:h:h:h')
let s:os = tolower(system('uname'))
let s:arch = tolower(system('uname -m'))

if !exists('s:instances')
  let s:instances = {}
endif

function! s:UrlEncode(str) abort
  return substitute(iconv(a:str, 'latin1', 'utf-8'),'[^A-Za-z0-9._~!$&''()*+,;=:@/-]','\="%".printf("%02X",char2nr(submatch(0)))','g')
endfunction

let s:slash = exists('+shellslash') ? '\' : '/'
function! s:UriFromBufnr(bufnr) abort
	let absolute = tr(bufname(a:bufnr), s:slash, '/')
	if absolute !~# '^\a\+:\|^/\|^$' && getbufvar(a:bufnr, 'buftype') =~# '^\%(nowrite\)\=$'
		let absolute = substitute(tr(getcwd(), s:slash, '/'), '/\=$', '/', '') . absolute
	endif
	return s:UriFromPath(absolute)
endfunction

function! s:UriFromPath(absolute) abort
	let absolute = a:absolute
	if has('win32') && absolute =~# '^\a://\@!'
		return 'file:///' . strpart(absolute, 0, 2) . s:UrlEncode(strpart(absolute, 2))
	elseif absolute =~# '^/'
		return 'file://' . s:UrlEncode(absolute)
	elseif absolute =~# '^\a[[:alnum:].+-]*:\|^$'
		return absolute
	else
		return ''
	endif
endfunction

function! s:BufferText(bufnr) abort
	return join(getbufline(a:bufnr, 1, '$'), "\n") . "\n"
endfunction

function! s:VimSendRequest(agent, request, ...) abort
	if empty(s:VimSendWithResult(a:agent, a:request)) && has_key(a:request, 'id') && has_key(a:agent.requests, a:request.id)
    call s:RejectRequest(remove(a:agent.requests, a:request.id), {'code': 257, 'message': 'Write failed'})
	endif
endfunction

function! copilot#agent#Result(request, callback) abort
	if has_key(a:request, 'resolve')
		call add(a:request.resolve, a:callback)
	elseif has_key(a:request, 'result')
		let a:request.waiting[timer_start(0, function('s:Callback', [a:request, 'result', a:callback]))] = 1
	endif
endfunction

function! s:RegisterWorkspaceFolderForBuffer(agent, buf) abort
	let root = getbufvar(a:buf, 'workspace_folder')
	if type(root) != v:t_string
		return
	endif
	let root = s:UriFromPath(substitute(root, '[\/]$', '', ''))
	if empty(root) || has_key(a:agent.workspaceFolders, root)
		return
	endif
	let a:agent.workspaceFolders[root] = v:true
endfunction
  
function! s:PreprocessParams(agent, params) abort
	let bufnr = v:null
	for doc in filter([a:params], '!empty(get(v:val, "bufnr", ""))')
		let bufnr = doc.bufnr
		let synced = a:agent.Attach(bufnr)
		let doc.uri = synced.uri
		let doc.version = get(synced, 'version', 0)
	endfor
	return bufnr
endfunction

function! s:AgentAttach(bufnr) dict abort
	if !bufloaded(a:bufnr)
		return {'uri': '', 'version': 0}
	endif
	let bufnr = a:bufnr
	let doc = {
		\ 'uri': s:UriFromBufnr(bufnr),
		\ 'version': getbufvar(bufnr, 'changedtick', 0),
		\ 'languageId': copilot#doc#LanguageForFileType(getbufvar(bufnr, '&filetype')),
		\ }
	if has_key(self.open_buffers, bufnr) && (
		\ self.open_buffers[bufnr].uri !=# doc.uri ||
		\ self.open_buffers[bufnr].languageId !=# doc.languageId)
		call self.Notify('textDocument/didClose', {'textDocument': {'uri': self.open_buffers[bufnr].uri}})
		call remove(self.open_buffers, bufnr)
	endif

	if !has_key(self.open_buffers, bufnr)
		call self.Notify('textDocument/didOpen', {'textDocument': extend({'text': s:BufferText(bufnr)}, doc)})
		let self.open_buffers[bufnr] = doc
	else
		call self.Notify('textDocument/didChange', {
			\ 'textDocument': {'uri': doc.uri, 'version': doc.version},
			\ 'contentChanges': [{'text': s:BufferText(bufnr)}]})
		let self.open_buffers[bufnr].version = doc.version
	endif
	return doc
endfunction
  
function! s:VimNotify(method, params) dict abort
	let request = {'method': a:method, 'params': a:params}
	if has_key(self, 'initialization_pending')
		call add(self.initialization_pending, request)
	else
		return s:VimSendWithResult(self, request)
	endif
endfunction

function! s:VimRequest(method, params, ...) dict abort
	if !exists('s:id')
		let s:id = 0
	endif
	let s:id += 1
	let params = deepcopy(a:params)
	call s:PreprocessParams(self, params)
	let request = {'method': a:method, 'params': params, 'id': s:id}
	if has_key(self, 'initialization_pending')
		call add(self.initialization_pending, request)
	else
		call copilot#util#Defer(function('s:VimSendRequest'), self, request)
	endif
	return call('s:SetUpRequest', [self, s:id, a:method, params] + a:000)
endfunction

function! s:AgentCall(method, params, ...) dict abort
	let request = call(self.Request, [a:method, a:params] + a:000)
	if a:0
		return request
	endif
	return request.Await()
endfunction

function! s:AgentCancel(request) dict abort
	if has_key(self.requests, get(a:request, 'id', ''))
		call remove(self.requests, a:request.id)
		call self.Notify('$/cancelRequest', {'id': a:request.id})
	endif
	if get(a:request, 'status', '') ==# 'running'
		let a:request.status = 'canceled'
	endif
endfunction

function! s:RequestAgent() dict abort
	return get(s:instances, self.agent_id, v:null)
endfunction
  
function! s:RequestCancel() dict abort
	let agent = self.Agent()
	if !empty(agent)
		call agent.Cancel(self)
	elseif get(self, 'status', '') ==# 'running'
		let self.status = 'canceled'
	endif
	return self
endfunction

function! s:SetUpRequest(agent, id, method, params, ...) abort
	let request = {
		\ 'agent_id': a:agent.id,
		\ 'id': a:id,
		\ 'method': a:method,
		\ 'params': a:params,
		\ 'resolve': [],
		\ 'reject': [],
		\ 'status': 'running',
		\ 'Cancel': function('s:RequestCancel'),
		\ 'Agent': function('s:RequestAgent'),
		\ }
	let a:agent.requests[a:id] = request
	let args = a:000[2:-1]
	if len(args)
		if !empty(a:1)
			call add(request.resolve, { v -> call(a:1, [v] + args)})
		endif
		if !empty(a:2)
			call add(request.reject, { v -> call(a:2, [v] + args)})
		endif
		return request
	endif
	if a:0 && !empty(a:1)
		call add(request.resolve, a:1)
	endif
	if a:0 > 1 && !empty(a:2)
		call add(request.reject, a:2)
	endif
	return request
endfunction

function! s:VimIsAttached(bufnr) dict abort
	return bufloaded(a:bufnr) && has_key(self.open_buffers, a:bufnr) ? v:true : v:false
endfunction

function! s:NvimAttach(bufnr) dict abort
	if !bufloaded(a:bufnr)
		return {'uri': '', 'version': 0}
	endif
	call luaeval('pcall(vim.lsp.buf_attach_client, _A[1], _A[2])', [a:bufnr, self.id])
	return luaeval('{uri = vim.uri_from_bufnr(_A), version = vim.lsp.util.buf_versions[_A]}', a:bufnr)
endfunction
  
function! s:NeoVimIsAttached(bufnr) dict abort
	return bufloaded(a:bufnr) ? luaeval('vim.lsp.buf_is_attached(_A[1], _A[2])', [a:bufnr, self.id]) : v:false
endfunction
  
function! s:NeoVimRequest(method, params, ...) dict abort
  "echom 'NeoVimRequest'
  "echom a:method
  "echom a:params
	let params = deepcopy(a:params)
	let bufnr = s:PreprocessParams(self, params)
	let id = eval("v:lua.require'_copilot'.lsp_request(self.id, a:method, params, bufnr)")
	if id isnot# v:null
		return call('s:SetUpRequest', [self, id, a:method, params] + a:000)
	endif
	if has_key(self, 'client_id')
		call copilot#agent#NeoVimExit(self.client_id, -1, -1)
	endif
	throw 'copilot#agent: LSP client not available'
endfunction
  
function! s:NeoVimClose() dict abort
	if !has_key(self, 'client_id')
			return
	endif
	return luaeval('vim.lsp.get_client_by_id(_A).stop()', self.client_id)
endfunction

function! s:NeoVimNotify(method, params) dict abort
	return eval("v:lua.require'_copilot'.rpc_notify(self.id, a:method, a:params)")
endfunction

function! copilot#agent#LspHandle(agent_id, request) abort
  if !has_key(s:instances, a:agent_id)
    return
  endif
  return s:OnVimMessage(s:instances[a:agent_id], a:request)
endfunction

function! s:VimClose() dict abort
	if !has_key(self, 'job')
		return
	endif
	let job = self.job
	if has_key(self, 'kill')
		call job_stop(job, 'kill')
		call copilot#logger#Warn('Agent forcefully terminated')
		return
	endif
	let self.kill = v:true
	let self.shutdown = self.Request('shutdown', {}, function(self.Notify, ['exit']))
	call timer_start(2000, { _ -> job_stop(job, 'kill') })
  call copilot#logger#Debug('Agent shutdown initiated')
endfunction

function! copilot#agent#Cancel(request) abort
	if type(a:request) == type({}) && has_key(a:request, 'Cancel')
		call a:request.Cancel()
	endif
endfunction

let s:vim_capabilities = {
	\ 'workspace': {'workspaceFolders': v:true}
	\ }

function! s:JsCommand(is_debug,server_path) abort
	if !has('nvim-0.6') && v:version < 900
		return [v:null, '', 'Vim version too old']
	endif
	let agent = get(g:, 'copilot_agent_command', '')
	if type(agent) == type('')
		let agent = [expand(agent)]
	endif
	if empty(agent) || !filereadable(agent[0])
		let agent = [a:server_path]
		if !filereadable(agent[0])
		return [v:null, '', 'Could not find resource/dist/server.js (bad install?)']
		endif
	elseif agent[0] !~# '\.js$'
		return [agent + ['--stdio']+[a:is_debug == 0 ? "" : "--lsp-debug"], '', '']
	endif
	let node = get(g:, 'copilot_node_command', '')
	if empty(node)
		let node = ['node']
	elseif type(node) == type('')
		let node = [expand(node)]
	endif
	if !executable(get(node, 0, ''))
		if get(node, 0, '') ==# 'node'
		return [v:null, '', 'Node.js not found in PATH']
		else
		return [v:null, '', 'Node.js executable `' . get(node, 0, '') . "' not found"]
		endif
	endif
	if get(g:, 'copilot_ignore_node_version')
		return [node + agent + ['--stdio']+[a:is_debug == 0 ? "" : "--lsp-debug"], '', '']
	endif
	let node_version = s:GetNodeVersion(node)
	let warning = ''
	if node_version.status != 0
		return [v:null, '', 'Node.js exited with status ' . node_version.status]
	endif
	if get(node, 0, '') !=# 'node'
		let upgrade_advice = 'Change g:copilot_node_command to'
	else
		let upgrade_advice = 'Upgrade to'
	endif
	if node_version.major == 0
		return [v:null, node_version.string, 'Could not determine Node.js version']
	elseif node_version.major < 16 || node_version.major == 16 && node_version.minor < 14 || node_version.major == 17 && node_version.minor < 3
		return [v:null, node_version.string, 'Node.js ' . node_version.string . ' is unsupported.  ' . upgrade_advice . ' 18.x or newer']
	elseif node_version.major < 18
		let warning = 'Node.js ' . node_version.string . ' support will soon be dropped.  ' . upgrade_advice . ' 18.x or newer'
	endif
	return [node + agent + ['--stdio']+[a:is_debug == 0 ? "" : "--lsp-debug"], node_version.string, warning]
endfunction

function! s:LogMessage(params, agent) abort
  " echom "LogMessage"
endfunction

function! s:NewVersion(params, agent) abort
  " echom "NewVersion"
endfunction

function! s:Progress(params, agent) abort
  if has_key(a:agent.progress, a:params.token)
    " call a:agent.progress[a:params.token](a:params.value)
  endif
endfunction

let s:notifications = {
      \ '$/progress': function('s:Progress'),
      \ 'gongfeng/server-log': function('s:LogMessage'),
      \ 'gongfeng/new-version': function('s:NewVersion'),
      \ }

function! copilot#agent#New(...) abort
	if exists("g:copilot_initialized")
		call copilot#logger#Info("Copilot already initialized")
		return
	endif
	call copilot#logger#Info("copilot#agent#New")
	let g:copilot_initialized = 1
	let opts = a:0 ? a:1 : {}
	let instance = {
    \ 'requests': {},
    \ 'workspaceFolders': {},
    \ 'status': {'status': 'Starting', 'message': ''},
    \ 'Attach': function('s:AgentAttach'),
    \ 'Cancel': function('s:AgentCancel'),
    \ 'Call': function('s:AgentCall'),
    \ }
	let instance.methods = copy(s:notifications)
	let is_debug = 0
	let is_js = 0

	if is_js == 1
		 let s:lsp_file_path = s:root . '/resource/dist/server.js'
		 let s:command =["node"]+ [s:lsp_file_path]+['--stdio']
		let [s:command, node_version, command_error] = s:JsCommand(is_debug,s:lsp_file_path)
		if len(command_error)
			if empty(s:command)
			  let instance.id = -1
			  let instance.startup_error = command_error
			  call copilot#logger#Error(command_error)
			  return instance
			else
			  let instance.node_version_warning = command_error
			  echohl WarningMsg
			  echomsg 'Gongfeng Copilot: ' . command_error
			  echohl NONE
			endif
		  endif
		  if !empty(node_version)
			let instance.node_version = node_version
		  endif
	else 
    if !has('nvim-0.6') && v:version < 900
      echoerr "Vim version too old,requires 9.0.0185 or higher"
      return
    endif
		let s:lsp_file_name = "language-server-linux-x64"
		if has('win32')
			let s:lsp_file_name = "language-server-win-x64.exe"
		else
			if s:os =~ 'darwin'
				if s:arch =~ 'x86_64'
					let s:lsp_file_name = "language-server-macos-x64"
				elseif s:arch =~ 'arm64'
					let s:lsp_file_name = "language-server-macos-arm64"
				endif
			elseif s:os =~ 'linux'
				let s:lsp_file_name = "language-server-linux-x64"
			endif
		endif
		let s:lsp_file_path = s:root . '/resource/bin/' . s:lsp_file_name
		if !filereadable(s:lsp_file_path)
			echoerr "Could not find " . s:lsp_file_path
			return
		endif
		if !has('win32')
			call copilot#lsp#EnablePermission(s:lsp_file_path)
		endif
		let s:command = [s:lsp_file_path]+[is_debug == 0 ? "" : "--lsp-debug"]
	endif
	let opts = {}
	let opts = {
		\ 'capabilities': {},
		\ 'initializationOptions': { 'pluginVersion': s:plugin_version},
		\ }
	let opts.workspaceFolders = []
	let settings = {}
	if has('nvim')
    let opts.clientInfo = { 'name': 'NeoVim', 'version': s:ide_version }
		let instance.open_buffers = {}
		call extend(instance, {
			\ 'Close': function('s:NeoVimClose'),
			\ 'Notify': function('s:NeoVimNotify'),
			\ 'Request': function('s:NeoVimRequest'),
			\ 'IsAttached': function('s:NeoVimIsAttached'),
			\ })
		let instance.client_id = eval("v:lua.require'_copilot'.lsp_start_client(s:command, keys(instance.methods), opts, settings)")
		let instance.id = instance.client_id
	else
    let opts.clientInfo = { 'name': 'Vim', 'version': s:ide_version }
		let state = {'headers': {}, 'mode': 'headers', 'buffer': ''}
    call extend(instance, {
      \ 'Notify': function('s:VimNotify'),
      \ 'Request': function('s:VimRequest'),
      \ 'Close': function('s:VimClose'),
      \ 'IsAttached': function('s:VimIsAttached'),
			\ })
		let instance.open_buffers = {}
		let instance.job = job_start(s:command, {
			\ 'in_mode': 'lsp',
			\ 'out_mode': 'lsp',
			\ 'out_cb': { j, d -> copilot#util#Defer(function('s:OnVimMessage'), instance, d) },
			\ 'err_cb': function('s:OnErr', [instance]),
			\ 'exit_cb': { j, d -> copilot#util#Defer(function('s:OnVimExit'), instance, d) },
			\ })
		let instance.id = job_info(instance.job).process
		let opts.capabilities = s:vim_capabilities
		let opts.processId = getpid()
		let request = instance.Request('initialize', opts, function('s:VimInitializeResult'), function('s:VimInitializeError'), instance)
    let instance.initialization_pending = []
    let initialize_request = {
		\ 'method': "initialize",
		\ 'params': opts
		\ }
    call copilot#logger#Info("[Request] " . json_encode(initialize_request))
	endif
	let s:instances[instance.id] = instance
	return instance
endfunction

function! s:OnVimMessage(agent, body, ...) abort
	if !has_key(a:body, 'method')
		return s:OnWholeResponse(a:agent, a:body)
	endif
  call copilot#logger#Info("[Notify]" . json_encode(a:body))
  if a:body.method ==# 'gongfeng/new-version'
    let g:copilot_new_version_params = a:body.params
  endif
endfunction

function! s:VimSendWithResult(agent, request) abort
	try
		call ch_sendexpr(a:agent.job, a:request)
		return v:true
	catch /^Vim\%((\a\+)\)\=:E906:/
		let a:agent.kill = v:true
		let job = a:agent.job
    call copilot#logger#Warn('Terminating agent after failed write')
		call job_stop(job)
		call timer_start(2000, { _ -> job_stop(job, 'kill') })
		return v:false
	catch /^Vim\%((\a\+)\)\=:E631:/
		return v:false
	endtry
endfunction

function! copilot#agent#WholeNotify(agent,method, params) abort
  let lspRequest = {
		\ 'method': a:method,
		\ 'params': a:params
		\ }
  call copilot#logger#Info("[Request] " . json_encode(lspRequest))
  return call(a:agent.Notify, [a:method, a:params])
endfunction

function! copilot#agent#WholeRequest(method, params, ...) abort
  let lspRequest = {
		\ 'method': a:method,
		\ 'params': a:params
		\ }
  call copilot#logger#Info("[Request] " . json_encode(lspRequest))
  let agent = copilot#Agent()
  return call(agent.Request, [a:method, a:params] + a:000)
endfunction

function! s:OnWholeResponse(agent, response, ...) abort
	let response = a:response
	let id = get(a:response, 'id', v:null)
	if !has_key(a:agent.requests, id)
		return
  call copilot#logger#Info("[Response] " . json_encode(response))
	endif
	let request = remove(a:agent.requests, id)
	if request.status ==# 'canceled'
		return
	endif
	if has_key(response, 'result')
		let request.waiting = {}
		let resolve = remove(request, 'resolve')
		call remove(request, 'reject')
		let request.status = 'success'
		let request.result = response.result
		for Cb in resolve
			let request.waiting[timer_start(0, function('s:Callback', [request, 'result', Cb]))] = 1
		endfor
	else
    call s:RejectRequest(request, response.error)
  endif
endfunction

function! s:RejectRequest(request, error) abort
  "echom "RejectRequest"
  "echom a:error
  if a:request.status ==# 'canceled'
    return
  endif
  let a:request.waiting = {}
  call remove(a:request, 'resolve')
  let reject = remove(a:request, 'reject')
  let a:request.status = 'error'
  let a:request.error = a:error
  for Cb in reject
    let a:request.waiting[timer_start(0, function('s:Callback', [a:request, 'error', Cb]))] = 1
  endfor
  let msg = 'Method ' . a:request.method . ' error with code' . a:error.code . ': ' . json_encode(a:error.message)
  if empty(reject)
    call copilot#logger#Error(msg)
  else
    call copilot#logger#Debug(msg)
  endif
endfunction

function! s:Callback(request, type, callback, timer) abort
	call remove(a:request.waiting, a:timer)
	if has_key(a:request, a:type)
		call a:callback(a:request[a:type])
	endif
endfunction

function! s:OnVimExit(agent, code, ...) abort
  call copilot#logger#Warn('lsp exited with status ' . a:code)
endfunction

function! s:OnErr(agent, ch, line, ...) abort
  if !has_key(a:agent, 'serverInfo')
    call copilot#logger#Bare('<-! ' . a:line)
  endif
endfunction

function! copilot#agent#NeoVimInit(agent_id, initialize_result) abort
	if !has_key(s:instances, a:agent_id)
		return
	endif
  call copilot#lsp#Initialized(s:instances[a:agent_id],a:initialize_result)
endfunction

function! copilot#agent#NeoVimExit(agent_id, code, signal) abort
	if !has_key(s:instances, a:agent_id)
		return
	endif
	let instance = remove(s:instances, a:agent_id)
	call s:OnVimExit(instance, a:code)
endfunction

function! copilot#agent#NeoVimResponse(agent_id, opts, ...) abort
	if !has_key(s:instances, a:agent_id)
		return
	endif
	call s:OnWholeResponse(s:instances[a:agent_id], a:opts)
endfunction

function! s:GetNodeVersion(command) abort
	let out = []
	let err = []
	let status = copilot#job#Stream(a:command + ['--version'], function('add', [out]), function('add', [err]))
	let string = matchstr(join(out, ''), '^v\zs\d\+\.[^[:space:]]*')
	if status != 0
		let string = ''
	endif
	let major = str2nr(string)
	let minor = str2nr(matchstr(string, '\.\zs\d\+'))
	return {'status': status, 'string': string, 'major': major, 'minor': minor}
endfunction

function! s:NeoVimInitializeResult(result, agent) abort
	call copilot#lsp#Initialized(a:agent,a:result)
endfunction

function! s:NeoVimInitializeError(result, agent) abort
  if a:error.code == s:error_exit
		let a:agent.startup_error = 'Agent exited with status ' . a:error.data.status
	else
		let a:agent.startup_error = 'Unexpected error ' . a:error.code . ' calling agent: ' . a:error.message
		call a:agent.Close()
	endif
endfunction

function! s:VimInitializeResult(result, agent) abort
	call copilot#lsp#Initialized(a:agent,a:result)
	for request in remove(a:agent, 'initialization_pending')
		call copilot#util#Defer(function('s:VimSendRequest'), a:agent, request)
	endfor
endfunction

function! s:VimInitializeError(error, agent) abort
	if a:error.code == s:error_exit
		let a:agent.startup_error = 'Agent exited with status ' . a:error.data.status
	else
		let a:agent.startup_error = 'Unexpected error ' . a:error.code . ' calling agent: ' . a:error.message
		call a:agent.Close()
	endif
endfunction
