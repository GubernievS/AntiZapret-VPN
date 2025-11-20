-- Fallback to TCP if UDP connection failed (policy.FORWARD only)
local M = {layer = {}}
M.timeout = 2 * sec
local ffi = require('ffi')
ffi.cdef("void kr_server_selection_init(struct kr_query *qry);")
function M.layer.produce(_, req, _)
	local qry = req.current_query
	if qry.flags.TCP or qry.flags.STUB then return end
	local now = ffi.C.kr_now()
	local deadline = qry.creation_time_mono + M.timeout
	if now > deadline then
		log_debug(ffi.C.LOG_GRP_NETWORK, 'UDP connection failed, fallback to TCP')
		qry.flags.TCP = true
		-- Hacky: we need to reset the server-selection state,
		-- so that forwarding mode can start.
		-- Fortunately context is on kr_request mempool, so we can leak it.
		ffi.C.kr_server_selection_init(qry);
	end
end
return M