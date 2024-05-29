local copilot = {}

copilot.lsp_start_client = function(cmd, handler_names, opts, settings)
	id = vim.lsp.start_client({
		cmd = cmd,
		name = 'copilot',
		init_options = opts.initializationOptions,
		get_language_id = function(bufnr, filetype)
			return vim.call('copilot#doc#LanguageForFileType', filetype)
		end,
		on_init = function(client, initialize_result)
			vim.call('copilot#agent#NeoVimInit', client.id, initialize_result)
		end,
		on_exit = function(code, signal, client_id)
			vim.schedule(function()
				vim.call('copilot#agent#NeoVimExit', client_id, code, signal)
			end)
		end,
	})
	return id
end

copilot.lsp_request = function(client_id, method, params, bufnr)
	local client = vim.lsp.get_client_by_id(client_id)
	if not client then
		return client.id
	end
	if bufnr == vim.NIL then
		bufnr = nil
	end
	local _, id
	_, id = client.request(method, params, function(err, result)
		vim.call('copilot#agent#NeoVimResponse', client_id, { id = id, error = err, result = result })
	end, bufnr)
	return id
end

copilot.rpc_request = function(client_id, method, params)
	local client = vim.lsp.get_client_by_id(client_id)
	if not client then
		return
	end
	local _, id
	_, id = client.rpc.request(method, params, function(err, result)
		vim.call('copilot#agent#NeoVimResponse', client_id, { id = id, error = err, result = result })
	end)
	return id
end

copilot.rpc_notify = function(client_id, method, params)
	local client = vim.lsp.get_client_by_id(client_id)
	if not client then
		return
	end
	return client.rpc.notify(method, params)
end

return copilot
