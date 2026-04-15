-- Fallback on non-NOERROR or timeout from the default resolver

local ffi = require('ffi')
local kres = require('kres')
ffi.cdef("void kr_server_selection_init(struct kr_query *qry);")

local M = {
	layer = {},
	action = policy.FORWARD({'1.1.1.1', '9.9.9.10', '77.88.8.8', '193.58.251.251'})
}

local fallback = {}

local function check_query(req)
	local qry = req:current()
	if not qry or qry.flags.CACHED then
		return nil
	end
	return qry
end

local function do_fallback(state, req, qry)
	local key = tostring(req)
	if fallback[key] then
		return false
	end
	fallback[key] = true

	local qname = kres.dname2str(qry.sname)
	local qtype = kres.tostring.type[qry.stype]
	event.after(0, function()
		cache.clear(qname, true)
	end)

	log_debug(ffi.C.LOG_GRP_POLICY, '[fallback] => fallback policy applied for %s %s', qname, qtype)

	-- Reset current forwarding
	if req.selection_context and req.selection_context.forwarding_targets then
		req.selection_context.forwarding_targets.len = 0
	end

	-- Reset failure counter
	if req.count_fail_row ~= nil then
		req.count_fail_row = 0
	end

	M.action(state, req)
	ffi.C.kr_server_selection_init(qry)

	return true
end

-- Produce this request before sending to upstream
function M.layer.produce(state, req, pkt)
	local qry = check_query(req)
	if not qry then
		return state
	end

	if not req.count_fail_row or req.count_fail_row == 0 then
		return state
	end

	do_fallback(state, req, qry)
	return state
end

-- Consume reply from upstream or from cache
function M.layer.consume(state, req, pkt)
	local qry = check_query(req)
	if not qry then
		return state
	end

	-- Timeout/transport errors
	if not pkt then
		if do_fallback(state, req, qry) then
			return kres.FAIL
		end
		return state
	end

	if pkt:rcode() == kres.rcode.NOERROR then
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
