
if exists('g:loaded_slime') || &cp || v:version < 700
  finish
endif
let g:loaded_slime = 1

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Configuration
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

if !exists("g:slime_target")
  let g:slime_target = "screen"
end

if !exists("g:slime_preserve_curpos")
  let g:slime_preserve_curpos = 0
end

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Screen
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:ScreenSend(config, text)
  call s:WritePasteFile(a:text)
  call system("screen -S " . shellescape(a:config["sessionname"]) . " -p " . shellescape(a:config["windowname"]) . " -X readreg p " . g:slime_paste_file)
  call system("screen -S " . shellescape(a:config["sessionname"]) . " -p " . shellescape(a:config["windowname"]) . " -X paste p")
endfunction

function! s:ScreenSessionNames(A,L,P)
  return system("screen -ls | awk '/Attached/ {print $1}'")
endfunction

function! s:ScreenConfig() abort
  if !exists("b:slime_config")
    let b:slime_config = {"sessionname": "", "windowname": "0"}
  end

  " screen needs a file, so set a default if not configured
  if !exists("g:slime_paste_file")
    let g:slime_paste_file = "$HOME/.slime_paste"
  end

  let b:slime_config["sessionname"] = input("screen session name: ", b:slime_config["sessionname"], "custom,<SNR>" . s:SID() . "_ScreenSessionNames")
  let b:slime_config["windowname"]  = input("screen window name: ",  b:slime_config["windowname"])
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Tmux
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:TmuxSend(config, text)
  let l:prefix = "tmux -L " . shellescape(a:config["socket_name"])
  " use STDIN unless configured to use a file
  if !exists("g:slime_paste_file")
    call system(l:prefix . " load-buffer -", a:text)
  else
    call s:WritePasteFile(a:text)
    call system(l:prefix . " load-buffer " . g:slime_paste_file)
  end
  call system(l:prefix . " paste-buffer -d -t " . shellescape(a:config["target_pane"]))
endfunction

function! s:TmuxPaneNames(A,L,P)
  let format = '#{pane_id} #{session_name}:#{window_index}.#{pane_index} #{window_name}#{?window_active, (active),}'
  return system("tmux -L " . shellescape(b:slime_config['socket_name']) . " list-panes -a -F " . shellescape(format))
endfunction

function! s:TmuxConfig() abort
  if !exists("b:slime_config")
    let b:slime_config = {"socket_name": "default", "target_pane": ":"}
  end

  let b:slime_config["socket_name"] = input("tmux socket name: ", b:slime_config["socket_name"])
  let b:slime_config["target_pane"] = input("tmux target pane: ", b:slime_config["target_pane"], "custom,<SNR>" . s:SID() . "_TmuxPaneNames")
  if b:slime_config["target_pane"] =~ '\s\+'
    let b:slime_config["target_pane"] = split(b:slime_config["target_pane"])[0]
  endif
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" whimrepl
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:WhimreplSend(config, text)
  call remote_send(a:config["server_name"], a:text)
endfunction

function! s:WhimreplConfig() abort
  if !exists("b:slime_config")
    let b:slime_config = {"server_name": "whimrepl"}
  end

  let b:slime_config["server_name"] = input("whimrepl server name: ", b:slime_config["server_name"])
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Helpers
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:SID()
  return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$')
endfun

function! s:WritePasteFile(text)
  " could check exists("*writefile")
  call system("cat > " . g:slime_paste_file, a:text)
endfunction

function! s:_EscapeText(text)
  if exists("&filetype")
    let custom_escape = "_EscapeText_" . substitute(&filetype, "[.]", "_", "g")
    if exists("*" . custom_escape)
      let result = call(custom_escape, [a:text])
    end
  end

  " use a:text if the ftplugin didn't kick in
  if !exists("result")
    let result = a:text
  end

  " return an array, regardless
  if type(result) == type("")
    return [result]
  else
    return result
  end
endfunction

function! s:SlimeGetConfig()
  if !exists("b:slime_config")
    if exists("g:slime_default_config")
      let b:slime_config = g:slime_default_config
    end
    call s:SlimeDispatch('Config')
  end
endfunction

function! s:SlimeSendOp(type, ...) abort
  call s:SlimeGetConfig()

  let sel_save = &selection
  let &selection = "inclusive"
  let rv = getreg('"')
  let rt = getregtype('"')

  if a:0  " Invoked from Visual mode, use '< and '> marks.
    silent exe "normal! `<" . a:type . '`>y'
  elseif a:type == 'line'
    silent exe "normal! '[V']y"
  elseif a:type == 'block'
    silent exe "normal! `[\<C-V>`]\y"
  else
    silent exe "normal! `[v`]y"
  endif

  call setreg('"', @", 'V')
  call s:SlimeSend(@")

  let &selection = sel_save
  call setreg('"', rv, rt)

  call s:SlimeRestoreCurPos()
endfunction

function! s:SlimeSendRange() range abort
  call s:SlimeGetConfig()

  let rv = getreg('"')
  let rt = getregtype('"')
  sil exe a:firstline . ',' . a:lastline . 'yank'
  call s:SlimeSend(@")
  call setreg('"', rv, rt)

  execute "normal! }j"
endfunction

function! s:SlimeSendLines(count) abort
  call s:SlimeGetConfig()

  let rv = getreg('"')
  let rt = getregtype('"')
  exe "norm! " . a:count . "yy"
  call s:SlimeSend(@")
  call setreg('"', rv, rt)

  execute "normal! }j"
endfunction

function! s:SlimeStoreCurPos()
  if g:slime_preserve_curpos == 1
    let s:cur = getcurpos()
  endif
endfunction

function! s:SlimeRestoreCurPos()
  if g:slime_preserve_curpos == 1
    call setpos('.', s:cur)
  endif
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Public interface
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:SlimeSend(text)
  call s:SlimeGetConfig()

  " this used to return a string, but some receivers (coffee-script)
  " will flush the rest of the buffer given a special sequence (ctrl-v)
  " so we, possibly, send many strings -- but probably just one
  let pieces = s:_EscapeText(a:text)
  for piece in pieces
    call s:SlimeDispatch('Send', b:slime_config, piece)
  endfor
endfunction

function! s:SlimeConfig() abort
  call inputsave()
  call s:SlimeDispatch('Config')
  call inputrestore()
endfunction

" delegation
function! s:SlimeDispatch(name, ...)
  let target = substitute(tolower(g:slime_target), '\(.\)', '\u\1', '') " Capitalize
  return call("s:" . target . a:name, a:000)
endfunction

function! s:SlimeRunCell() abort
    " Run a cell delimited by g:cell_delimiter
    call s:SlimeGetConfig()
    execute "silent :?" . g:slime_cell_delimiter . "?;/" . g:slime_cell_delimiter . "/y a"
    "silent :?##?;/##/y a
    ']
    execute "normal! j"
    call s:SlimeSend(@a)
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Setup key bindings
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

command -bar -nargs=0 SlimeConfig call s:SlimeConfig()
command -range -bar -nargs=0 SlimeSend <line1>,<line2>call s:SlimeSendRange()
command -nargs=+ SlimeSend1 call s:SlimeSend(<q-args> . "\r")
command -nargs=0 SlimeRunCell call s:SlimeRunCell()

noremap <SID>Operator :<c-u>call <SID>SlimeStoreCurPos()<cr>:set opfunc=<SID>SlimeSendOp<cr>g@

noremap <unique> <script> <silent> <Plug>SlimeRegionSend :<c-u>call <SID>SlimeSendOp(visualmode(), 1)<cr>}j
noremap <unique> <script> <silent> <Plug>SlimeLineSend :<c-u>call <SID>SlimeSendLines(v:count1)<cr>}j
noremap <unique> <script> <silent> <Plug>SlimeMotionSend <SID>Operator
noremap <unique> <script> <silent> <Plug>SlimeParagraphSend <SID>Operatorip}j
noremap <unique> <script> <silent> <Plug>SlimeConfig :<c-u>SlimeConfig<cr>
noremap <unique> <script> <silent> <Plug>SlimeRunCell :<c-u>call <SID>SlimeRunCell()<cr>

if !exists("g:slime_no_mappings") || !g:slime_no_mappings
  "exists("g:slime_cell_delimiter")
  if !hasmapto('<Plug>SlimeRunCell', 'n')
      nmap <c-c><Enter> <Plug>SlimeRunCell
  endif

  if !hasmapto('<Plug>SlimeRegionSend', 'x')
    xmap <c-c><c-c> <Plug>SlimeRegionSend }j
  endif

  if !hasmapto('<Plug>SlimeParagraphSend', 'n')
    nmap <c-c><c-c> <Plug>SlimeParagraphSend }j
  endif

  if !hasmapto('<Plug>SlimeConfig', 'n')
    nmap <c-c>v <Plug>SlimeConfig
  endif
endif
