
function! slime#targets#neovim#config() abort

  " unlet current config if its jobid doesn't exist
  if exists("b:slime_config")
    if !s:ValidConfig(b:slime_config)
      unlet b:slime_config
    endif
  endif

  if !exists("b:slime_config")
    let last_channels = get(g:, 'slime_last_channel', [])
    let most_recent_channel = get(last_channels, -1, {})

    let last_pid = get(most_recent_channel, 'pid', '')
    let last_job = get(most_recent_channel, 'jobid', '')
    let b:slime_config =  {"jobid":  last_job, "pid": last_pid }
  endif

  " include option to input pid
  if exists("g:slime_input_pid") && g:slime_input_pid
    let default_pid = jobpid(b:slime_config["jobid"])
    if !empty(default_pid)
      let default_pid = str2nr(default_pid)
    endif
    let pid_in = input("Configuring vim-slime. Input pid: ", default_pid)
    let id_in = s:translate_pid_to_id(pid_in)
  else
    if exists("g:slime_get_jobid")
      let id_in = g:slime_get_jobid()
    else
      let default_jobid = b:slime_config["jobid"]
      if !empty(default_jobid)
        let default_jobid = str2nr(default_jobid)
      endif
      let id_in = input("Configuring vim-slime. Input jobid: ", default_jobid)
      let id_in = str2nr(id_in)
    endif
    let pid_in = s:translate_id_to_pid(id_in)
  endif

  let b:slime_config["jobid"] = id_in
  let b:slime_config["pid"] = pid_in

  if exists("b:slime_config")
    if !s:ValidConfig(b:slime_config)
      unlet b:slime_config
    endif
  endif

endfunction

function! slime#targets#neovim#send(config, text)
  if  s:ValidConfig()

    " Neovim jobsend is fully asynchronous, it causes some problems with
    " iPython %cpaste (input buffering: not all lines sent over)
    " So this `write_paste_file` can help as a small lock & delay
    call slime#common#write_paste_file(a:text)
    call chansend(str2nr(a:config["jobid"]), split(a:text, "\n", 1))
    " if b:slime_config is {"jobid": ""} and not configured
    " then unset it for automatic configuration next time
    if b:slime_config["jobid"]  == ""
      unlet b:slime_config
    endif


  else "remove invalid configs
    unlet b:slime_config
  endif
endfunction

function! slime#targets#neovim#SlimeAddChannel()
  if !exists("g:slime_last_channel")
    let g:slime_last_channel = [{'jobid': &channel, 'pid': jobpid(&channel)}]
  else
    call add(g:slime_last_channel, {'jobid': &channel, 'pid': jobpid(&channel)})
  endif
endfunction

function! slime#targets#neovim#SlimeClearChannel()
  let current_buffer_jobid = &channel

  let related_bufs = filter(getbufinfo(), {_, val -> has_key(val['variables'], "slime_config")
        \ && get(val['variables']['slime_config'], 'jobid', -2) == current_buffer_jobid})

  for buf in related_bufs
    call setbufvar(buf['bufnr'], 'slime_config', {})
  endfor

  if !exists("g:slime_last_channel")
    if exists("b:slime_config")
      unlet b:slime_config
    endif
    return
  elseif len(g:slime_last_channel) == 1
    unlet g:slime_last_channel
    if exists("b:slime_config")
      unlet b:slime_config
    endif
  else
    let bufinfo = s:get_filter_bufinfo()

    " tests if using a version of Neovim that
    " doesn't automatically close buffers when closed
    " or there is no autocommand that does that
    if len(bufinfo) == len(g:slime_last_channel)
      call filter(bufinfo, {_, val -> val != current_buffer_jobid})
    endif

    call filter(g:slime_last_channel, {_, val -> index(bufinfo, str2nr(val["jobid"])) >= 0})

  endif
endfunction

function! s:get_filter_bufinfo()
  let bufinfo = getbufinfo()
  "getting terminal buffers

  call filter(bufinfo, {_, val -> has_key(val['variables'], "terminal_job_id")
        \ && has_key(val['variables'], "terminal_job_pid")
        \    && get(val,"listed",0)})
  " only need the job id
  call map(bufinfo, {_, val -> val["variables"]["terminal_job_id"] })

  return bufinfo
endfunction

function! s:translate_pid_to_id(pid)
  for ch in g:slime_last_channel
    if ch['pid'] == a:pid
      return ch['jobid']
    endif
  endfor
  return -1
endfunction

function! s:translate_id_to_pid(id)
  let pid_out = -1
  try
    let pid_out = jobpid(a:id)
  catch /E900: Invalid channel id/
    let pid_out = -1
  endtry
  return pid_out
endfunction


" "checks that a configuration is valid
" returns boolean of whether the supplied config is valid
function! s:ValidConfig(config) abort

  if s:NotExistsLastChannel()
    echo "\nTerminal not detected."
    return 0
  endif

  if !exists("a:config") ||  a:config is v:null
    echo "\nConfig does not exist."
    return 0
  endif

  " Ensure the config is a dictionary and a previous channel exists
  if type(a:config) != v:t_dict
    echo "\nConfig type not valid."
    return 0
  endif

  if empty(a:config)
    echo "\nConfig is empty."
    return 0
  endif

  " Ensure the correct keys exist within the configuration
  if !(has_key(a:config, 'jobid'))
    echo "\nConfigration object lacks 'jobid'."
    return 0
  endif

  if a:config["jobid"] == -1  "the id wasn't found translate_pid_to_id
    echo "\nNo matching job id for the provided pid."
    return 0
  endif

  if !(index( s:channel_to_array(g:slime_last_channel), a:config['jobid']) >= 0)
    echo "\nJob ID not found."
    return 0
  endif

  if !(index(s:get_filter_bufinfo(), a:config['jobid']) >= 0)
    echo "\nJob ID not found."
    return 0
  endif

  if empty(jobpid(a:config['jobid']))
    echo "\nJob ID not linked to a PID."
    return 0
  endif

  return 1

endfunction
