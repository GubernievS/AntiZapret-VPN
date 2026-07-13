-- Fallback on non-NOERROR or empty A answer from the default resolver

local ffi = require('ffi')
local kres = require('kres')
ffi.cdef("void kr_server_selection_init(struct kr_query *qry);")

local M = {
	layer = {},
	action = policy.FORWARD({'1.1.1.1', '9.9.9.10', '76.76.2.0', '193.58.251.251'})
}

local fallback = {}

local function do_fallback(state, req, qry)
	local key = tostring(req)
	if fallback[key] then
		return false
	end
	fallback[key] = true

	local qname = kres.dname2str(qry.sname)
	local qtype = kres.tostring.type[qry.stype]
	log_debug(ffi.C.LOG_GRP_POLICY, '[fallback] => fallback policy applied for %s %s', qname, qtype)

	-- Reset cache
	cache.clear(qname, true)

	-- Reset current DNS records
	req.answ_selected.len = 0
	req.auth_selected.len = 0
	req.add_selected.len = 0

	-- Reset current forwarding
	req.selection_context.forwarding_targets.len = 0

	-- Reset failure counter
	req.count_fail_row = 0

	M.action(state, req)
	ffi.C.kr_server_selection_init(qry)

	return true
end

-- Consume reply from upstream or from cache
function M.layer.consume(state, req, pkt)
	local qry = req:current()
	if not qry or qry.flags.CACHED then
		return state
	end

	if pkt:rcode() == kres.rcode.NOERROR
		and not (qry.stype == kres.type.A and pkt:ancount() == 0) then
		return state
	end

	if do_fallback(state, req, qry) then
		return kres.FAIL
	end
	return state
end

-- Finish for this request
function M.layer.finish(state, req)
	local key = tostring(req)
	fallback[key] = nil
	return state
end

return M
