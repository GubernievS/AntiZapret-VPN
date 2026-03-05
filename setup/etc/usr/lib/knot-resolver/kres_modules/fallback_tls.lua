-- Fallback to TLS forwarder on non-NOERROR response from default upstream

local ffi = require('ffi')
local kres = require('kres')
ffi.cdef("void kr_server_selection_init(struct kr_query *qry);")

local M = {
	layer = {},
	action = policy.TLS_FORWARD({
		-- TLS fallback forwarders
		{'1.1.1.1', hostname='cloudflare-dns.com'},
		{'9.9.9.10', hostname='dns.quad9.net'},
		{'76.76.2.0', hostname='p0.freedns.controld.com'},
		{'86.54.11.100', hostname='unfiltered.joindns4.eu'}
	}),
}

function M.layer.consume(state, req, pkt)
	if state == kres.FAIL then
		return state
	end

	local qry = req:current()

	-- Only for forward / stub queries
	if not qry.flags.FORWARD and not qry.flags.STUB then
		return state
	end

	-- Skip cached answers, TLS fallback forwarders and NOERROR responses
	local rcode = pkt:rcode()
	if qry.flags.CACHED or qry.flags.TCP or rcode == kres.rcode.NOERROR then
		return state
	end

	-- Clear cache for this domain after cache_stash runs
	local domain = kres.dname2str(qry.sname)
	event.after(0, function()
		cache.clear(domain, true)
	end)

	log_debug(ffi.C.LOG_GRP_POLICY, '[fallback] => domain %s, rcode %s, switching to TLS fallback forwarders', domain, tostring(rcode))

	-- Replace current forwarding to TLS fallback forwarders
	if req.selection_context and req.selection_context.forwarding_targets then
		req.selection_context.forwarding_targets.len = 0
	end

	-- Reset failure counter for this request
	if req.count_fail_row ~= nil then
		req.count_fail_row = 0
	end

	M.action(state, req)
	ffi.C.kr_server_selection_init(qry)

	return kres.FAIL
end

return M