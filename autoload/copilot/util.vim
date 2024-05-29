scriptencoding utf-8

let s:deferred = []

function! copilot#util#Defer(fn, ...) abort
  call add(s:deferred, function(a:fn, a:000))
  return timer_start(0, function('s:RunDefer'))
endfunction

function! s:RunDefer(...) abort
  if empty(s:deferred)
    return
  endif
  let Fn = remove(s:deferred, 0)
  call timer_start(0, function('s:RunDefer'))
  call call(Fn, [])
endfunction
