if !exists('g:copilot_log_file')
  let g:copilot_log_file = tempname() . '-copilot.log'
  try
    call writefile([], g:copilot_log_file)
  catch
  endtry
endif

let s:logs = []

function! copilot#logger#BufReadCmd() abort
  try
    setlocal modifiable noreadonly
    call deletebufline('', 1, '$')
    if !empty(s:logs)
      call setline(1, s:logs)
    endif
  finally
    setlocal buftype=nofile bufhidden=wipe nobuflisted nomodified nomodifiable
  endtry
endfunction

let s:level_prefixes = ['', '[ERROR] ', '[WARN] ', '[INFO] ', '[DEBUG] ', '[DEBUG] ']

function! copilot#logger#Raw(level, message) abort
  let lines = type(a:message) == v:t_list ? copy(a:message) : split(a:message, "\n", 1)
  let lines[0] = strftime('[%Y-%m-%d %H:%M:%S] ') . get(s:level_prefixes, a:level, '[UNKNOWN] ') . get(lines, 0, '')
  try
    if !filewritable(g:copilot_log_file)
      return
    endif
    call map(lines, { k, L -> type(L) == v:t_func ? call(L, []) : L })
    call extend(s:logs, lines)
    let overflow = len(s:logs) - get(g:, 'copilot_log_history', 500)
    if overflow > 0
      call remove(s:logs, 0, overflow - 1)
    endif
	  let delay = 5000
	  call timer_stop(get(g:, '_copilot_log_timer', -1))
	  let g:_copilot_log_timer = timer_start(delay, function('s:CopilotWriteFile'))
  catch
  endtry
endfunction


function! s:CopilotWriteFile(timer) abort
	call writefile(s:logs, g:copilot_log_file)
  unlet! g:_copilot_log_timer
endfunction

function! copilot#logger#Debug(...) abort
  call copilot#logger#Raw(4, a:000)
endfunction

function! copilot#logger#Info(...) abort
  call copilot#logger#Raw(3, a:000)
endfunction

function! copilot#logger#Warn(...) abort
  call copilot#logger#Raw(2, a:000)
endfunction

function! copilot#logger#Error(...) abort
  call copilot#logger#Raw(1, a:000)
endfunction

function! copilot#logger#Bare(...) abort
  call copilot#logger#Raw(0, a:000)
endfunction
