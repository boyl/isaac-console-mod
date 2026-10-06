// Minimal Chrome DevTools Protocol client for the Nexus upload flow.
// Zero dependencies: Node 22+ ships a global WebSocket and fetch.

export async function findPageTarget(port) {
  const response = await fetch(`http://127.0.0.1:${port}/json/list`);
  if (!response.ok) throw new Error(`CDP /json/list returned HTTP ${response.status}`);
  const targets = await response.json();
  const page = targets.find((target) => target.type === 'page');
  if (!page) throw new Error('Chrome exposes no page target; start it with --remote-debugging-port.');
  return page;
}

export class Cdp {
  constructor(socket) {
    this.socket = socket;
    this.nextId = 0;
    this.pending = new Map();
  }

  static async connect(webSocketUrl) {
    const socket = new WebSocket(webSocketUrl);
    await new Promise((resolve, reject) => {
      socket.addEventListener('open', resolve, { once: true });
      socket.addEventListener('error', () => reject(new Error(`Could not open the CDP WebSocket at ${webSocketUrl}`)), { once: true });
    });
    const cdp = new Cdp(socket);
    socket.addEventListener('message', (event) => {
      const message = JSON.parse(event.data);
      if (!message.id || !cdp.pending.has(message.id)) return;
      const { resolve, reject } = cdp.pending.get(message.id);
      cdp.pending.delete(message.id);
      if (message.error) reject(new Error(`${message.error.message} (${JSON.stringify(message.error)})`));
      else resolve(message.result);
    });
    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');
    await cdp.send('DOM.enable');
    return cdp;
  }

  send(method, params = {}) {
    const id = ++this.nextId;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.socket.send(JSON.stringify({ id, method, params }));
    });
  }

  async evaluate(expression, { byValue = true, awaitPromise = true } = {}) {
    const result = await this.send('Runtime.evaluate', {
      expression,
      returnByValue: byValue,
      awaitPromise,
      userGesture: true,
    });
    if (result.exceptionDetails) {
      const description = result.exceptionDetails.exception?.description || JSON.stringify(result.exceptionDetails);
      throw new Error(`Evaluation failed: ${description}`);
    }
    return byValue ? result.result.value : result.result;
  }

  async navigate(url, { timeoutMs = 60000 } = {}) {
    await this.send('Page.navigate', { url });
    await this.waitFor(
      { timeoutMs, description: `navigation to ${url}` },
      `document.readyState === 'complete'`,
    );
  }

  async waitFor({ timeoutMs = 60000, intervalMs = 500, description = 'condition' }, expression) {
    const deadline = Date.now() + timeoutMs;
    let lastError = null;
    for (;;) {
      try {
        if (await this.evaluate(`!!(${expression})`)) return true;
        lastError = null;
      } catch (error) {
        lastError = error;
      }
      if (Date.now() > deadline) {
        throw new Error(`Timed out after ${timeoutMs} ms waiting for ${description}${lastError ? ` (last error: ${lastError.message})` : ''}`);
      }
      await new Promise((resolve) => setTimeout(resolve, intervalMs));
    }
  }

  async screenshot(path) {
    const { data } = await this.send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true });
    return { path, bytes: Buffer.from(data, 'base64') };
  }

  async setFileInputs(index, files) {
    const handle = await this.evaluate(
      `(() => { const inputs = [...document.querySelectorAll('input[type=file]')]; return inputs[${index}] || null; })()`,
      { byValue: false },
    );
    const objectId = handle.objectId;
    if (!objectId) throw new Error(`No file input at index ${index}`);
    await this.send('DOM.setFileInputFiles', { files, objectId });
    return true;
  }
}

export function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
