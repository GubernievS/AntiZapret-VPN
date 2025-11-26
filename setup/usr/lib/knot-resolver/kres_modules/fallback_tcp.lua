-- Fallback to TCP if UDP connection failed (for policy.FORWARD/policy.STUB only)
local ffi = require('ffi')
ffi.cdef("void kr_server_selection_init(struct kr_query *qry);")
local M = {}
M.layer = {}
M.timeout = 1 * sec
M.layer.produce = function(state, req)
	local qry = req:current()
	if qry.flags.TCP then return state end
	local now = ffi.C.kr_now()
	local deadline = qry.creation_time_mono + M.timeout
	if now > deadline then
		log_debug(ffi.C.LOG_GRP_MODULE, 'UDP connection failed: fallback to TCP')
		qry.flags.TCP = true
		ffi.C.kr_server_selection_init(qry);
	end
	return state
end
return M