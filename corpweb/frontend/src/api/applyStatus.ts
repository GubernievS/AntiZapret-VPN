/**
 * Wait for all nodes to confirm apply of a changed path.
 * Uses fetch + ReadableStream (not EventSource, since EventSource doesn't support auth headers).
 */
export async function waitForApply(path: string): Promise<{ status: string; warning?: string }> {
  const token = localStorage.getItem('access_token');
  try {
    const resp = await fetch(`/api/v1/apply-status/stream?path=${encodeURIComponent(path)}`, {
      headers: { Authorization: `Bearer ${token}` },
    });

    if (!resp.ok || !resp.body) {
      return { status: 'ready' };
    }

    const reader = resp.body.getReader();
    const decoder = new TextDecoder();

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      const text = decoder.decode(value);
      for (const line of text.split('\n')) {
        if (line.startsWith('data:')) {
          try {
            const data = JSON.parse(line.slice(5).trim());
            if (data.status === 'ready') {
              reader.cancel();
              return data;
            }
          } catch {
            // ignore parse errors
          }
        }
      }
    }
  } catch {
    // fall through to default return
  }
  return { status: 'ready' };
}
