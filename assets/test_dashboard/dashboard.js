const state = {
  token: null,
  clientId: null,
  streamToken: null,
  ws: null,
  wsOpenPromise: null,
  poll: null,
  lastEventPayload: null,
  eventWaiters: []
};
const $ = (id) => document.getElementById(id);
function setText(id, value) { $(id).textContent = value; }
function log(message, data) {
  const line = `[${new Date().toLocaleTimeString()}] ${message}` + (data ? `\n${JSON.stringify(data, null, 2)}` : '');
  $('log').textContent = `${line}\n\n${$('log').textContent}`.slice(0, 8000);
}
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function fetchJson(path, options = {}) {
  const headers = Object.assign({'content-type': 'application/json'}, options.headers || {});
  if (state.token) headers.authorization = `Bearer ${state.token}`;
  const response = await fetch(path, Object.assign({}, options, { headers }));
  const text = await response.text();
  const body = text ? JSON.parse(text) : {};
  if (!response.ok) throw new Error(`${path} ${response.status}: ${text}`);
  return body;
}
async function ensurePair() {
  if (!state.token) {
    state.token = localStorage.getItem('mimicamTestToken');
    state.clientId = localStorage.getItem('mimicamTestClientId');
  }
  if (state.token) {
    try {
      await fetchJson('/test/status', { method: 'GET' });
      setText('pairState', 'hazır');
      return;
    } catch (_) {
      localStorage.removeItem('mimicamTestToken');
      localStorage.removeItem('mimicamTestClientId');
      state.token = null;
      state.clientId = null;
    }
  }
  const pub = await fetchJson('/status/public', { method: 'GET', headers: {} });
  const paired = await fetchJson('/pair/confirm', {
    method: 'POST',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify({
      pairingNonce: pub.pairingNonce,
      clientName: 'Browser test',
      deviceId: `browser-${Date.now()}`
    })
  });
  state.token = paired.trustedClientToken || paired.sessionToken;
  state.clientId = paired.clientId;
  localStorage.setItem('mimicamTestToken', state.token);
  localStorage.setItem('mimicamTestClientId', state.clientId);
  setText('pairState', 'hazır');
  log('Pair tamam', { clientId: state.clientId, capabilities: paired.capabilities });
}
async function startLive() {
  await ensurePair();
  const session = await fetchJson('/session/start', {
    method: 'POST',
    body: JSON.stringify({ clientId: state.clientId, video: true, audio: true })
  });
  state.streamToken = session.streamToken;
  $('video').src = `/video?streamToken=${encodeURIComponent(state.streamToken)}&t=${Date.now()}`;
  $('audio').src = `/audio?streamToken=${encodeURIComponent(state.streamToken)}&t=${Date.now()}`;
  setText('videoState', 'açık');
  setText('audioState', 'başlıyor');
  $('audio').play().then(() => setText('audioState', 'çalıyor')).catch((error) => {
    setText('audioState', 'dokun ve play');
    log('Tarayıcı autoplay engelledi, audio kontrolünden play yap', { error: error.message });
  });
  openEvents();
  startPolling();
  log('Canlı stream başladı', session);
}
async function resetServerTestState() {
  if (state.ws) {
    try { state.ws.close(); } catch (_) {}
    state.ws = null;
  }
  $('video').removeAttribute('src');
  $('audio').removeAttribute('src');
  $('video').load?.();
  $('audio').load?.();
  state.streamToken = null;
  state.lastEventPayload = null;
  state.eventWaiters.splice(0).forEach((waiter) => {
    clearTimeout(waiter.timer);
    waiter.resolve(null);
  });
  const result = await fetchJson('/test/reset', { method: 'POST', body: '{}' });
  setText('videoState', 'kapalı');
  setText('audioState', 'kapalı');
  setText('wsState', 'kapalı');
  log('Test runtime temizlendi', result.diagnostics?.clients);
  await sleep(500);
  return result;
}
function openEvents() {
  if (!state.token) return Promise.resolve(false);
  if (state.ws && state.ws.readyState === WebSocket.OPEN) {
    return Promise.resolve(true);
  }
  if (state.ws && state.ws.readyState === WebSocket.CONNECTING && state.wsOpenPromise) {
    return state.wsOpenPromise;
  }
  if (state.ws) state.ws.close();
  const scheme = location.protocol === 'https:' ? 'wss' : 'ws';
  state.wsOpenPromise = new Promise((resolve) => {
    state.ws = new WebSocket(`${scheme}://${location.host}/ws/events?token=${encodeURIComponent(state.token)}`);
    state.ws.binaryType = 'arraybuffer';
    let settled = false;
    const finish = (ok) => {
      if (settled) return;
      settled = true;
      clearTimeout(readyTimer);
      state.wsOpenPromise = null;
      resolve(ok);
    };
    const readyTimer = setTimeout(() => finish(false), 4000);
    state.ws.onopen = () => {
      setText('wsState', 'bağlı');
      log('WebSocket bağlı');
      finish(true);
    };
    state.ws.onclose = () => {
      setText('wsState', 'kapalı');
      log('WebSocket kapandı');
      finish(false);
    };
    state.ws.onerror = () => {
      setText('wsState', 'hata');
      log('WebSocket hata verdi');
      finish(false);
    };
    state.ws.onmessage = (event) => {
      if (typeof event.data !== 'string') {
        log('Binary legacy event geldi', { bytes: event.data.byteLength || event.data.size || event.data.length || 0 });
        return;
      }
      $('event').textContent = event.data;
      let payload = null;
      try { payload = JSON.parse(event.data); } catch (_) { payload = { raw: event.data }; }
      state.lastEventPayload = payload;
      settleEventWaiters(payload);
      log('Event geldi', payload);
    };
  });
  return state.wsOpenPromise;
}
function waitForEvent(predicate, timeoutMs = 4500) {
  if (state.lastEventPayload && predicate(state.lastEventPayload)) {
    return Promise.resolve(state.lastEventPayload);
  }
  return new Promise((resolve) => {
    const waiter = {
      predicate,
      resolve,
      timer: setTimeout(() => {
        state.eventWaiters = state.eventWaiters.filter((entry) => entry !== waiter);
        resolve(null);
      }, timeoutMs)
    };
    state.eventWaiters.push(waiter);
  });
}
function settleEventWaiters(payload) {
  const waiting = state.eventWaiters;
  state.eventWaiters = [];
  for (const waiter of waiting) {
    if (waiter.predicate(payload)) {
      clearTimeout(waiter.timer);
      waiter.resolve(payload);
    } else {
      state.eventWaiters.push(waiter);
    }
  }
}
async function playTone() {
  await ensurePair();
  const response = await fetch('/test/audio-tone?durationMs=1800&frequencyHz=880&amplitude=0.45', {
    headers: { authorization: `Bearer ${state.token}` }
  });
  if (!response.ok) throw new Error(`/test/audio-tone ${response.status}`);
  const blob = await response.blob();
  $('audio').src = URL.createObjectURL(blob);
  await $('audio').play();
  setText('audioState', 'test tonu');
  log('Test tonu çalındı');
}
async function sendAlert(message) {
  await ensurePair();
  await openEvents();
  const marker = `web-health-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const text = message || `MimiCam tarayıcı test bildirimi ${new Date().toLocaleTimeString()} ${marker}`;
  const startedAt = performance.now();
  const eventWait = waitForEvent((payload) => payload && payload.message === text, 4500);
  const result = await fetchJson('/test/alert', {
    method: 'POST',
    body: JSON.stringify({ message: text })
  });
  const event = await eventWait;
  const measured = {
    ok: !!event,
    latencyMs: event ? Math.round(performance.now() - startedAt) : null,
    deliveredWebSocketClients: result.deliveredWebSocketClients,
    event
  };
  log('Sentetik bildirim gönderildi', measured);
  return measured;
}
async function runProbe() {
  await ensurePair();
  const result = await fetchJson('/test/probe', {
    method: 'POST',
    body: JSON.stringify({
      startRuntime: true,
      waitMs: 2200,
      requireVideo: true,
      requireAudio: true,
      emitAlert: true,
      requireEvents: true,
      requireEventDelivery: state.ws && state.ws.readyState === WebSocket.OPEN
    })
  });
  $('diag').textContent = JSON.stringify(result, null, 2);
  log('Probe tamam', result.checks);
  return result;
}
async function refreshStatus() {
  if (!state.token) return;
  const status = await fetchJson('/test/status', { method: 'GET' });
  $('diag').textContent = JSON.stringify(status, null, 2);
  if (status.video && status.video.lastClientWriteAgeMs != null) setText('videoState', `${status.video.lastJpegBytes || 0} B`);
  if (status.audio && status.audio.lastChunkAgeMs != null) setText('audioState', `${status.audio.lastChunkBytes || 0} B`);
  return status;
}
function startPolling() {
  if (state.poll) clearInterval(state.poll);
  state.poll = setInterval(() => refreshStatus().catch((error) => log('Status alınamadı', { error: error.message })), 1500);
  refreshStatus().catch((error) => log('Status alınamadı', { error: error.message }));
}
function appendBytes(left, right) {
  const merged = new Uint8Array(left.length + right.length);
  merged.set(left);
  merged.set(right, left.length);
  return merged;
}
function concatChunks(chunks, totalBytes) {
  const merged = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    merged.set(chunk, offset);
    offset += chunk.length;
  }
  return merged;
}
function findMarker(bytes, first, second, from = 0) {
  for (let index = Math.max(0, from); index < bytes.length - 1; index++) {
    if (bytes[index] === first && bytes[index + 1] === second) return index;
  }
  return -1;
}
async function readWithTimeout(reader, timeoutMs) {
  return Promise.race([
    reader.read(),
    sleep(timeoutMs).then(() => ({ timeout: true }))
  ]);
}
async function decodeJpegFrame(jpeg) {
  const startedAt = performance.now();
  const blob = new Blob([jpeg], { type: 'image/jpeg' });
  const url = URL.createObjectURL(blob);
  try {
    const image = new Image();
    image.decoding = 'async';
    image.src = url;
    await image.decode();
    const canvas = $('videoProbeCanvas');
    const width = Math.max(1, Math.min(160, image.naturalWidth || image.width));
    const height = Math.max(1, Math.round(width * ((image.naturalHeight || image.height) / Math.max(1, image.naturalWidth || image.width))));
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext('2d', { willReadFrequently: true });
    context.drawImage(image, 0, 0, width, height);
    const data = context.getImageData(0, 0, width, height).data;
    let min = 255;
    let max = 0;
    let sum = 0;
    let sumSquares = 0;
    let count = 0;
    for (let offset = 0; offset < data.length; offset += 16) {
      const luma = 0.2126 * data[offset] + 0.7152 * data[offset + 1] + 0.0722 * data[offset + 2];
      min = Math.min(min, luma);
      max = Math.max(max, luma);
      sum += luma;
      sumSquares += luma * luma;
      count++;
    }
    const averageLuma = count ? sum / count : 0;
    const variance = count ? Math.max(0, sumSquares / count - averageLuma * averageLuma) : 0;
    return {
      decoded: true,
      width: image.naturalWidth || image.width,
      height: image.naturalHeight || image.height,
      averageLuma: Number(averageLuma.toFixed(1)),
      lumaStdDev: Number(Math.sqrt(variance).toFixed(1)),
      contrast: Number((max - min).toFixed(1)),
      decodeMs: Math.round(performance.now() - startedAt)
    };
  } finally {
    URL.revokeObjectURL(url);
  }
}
async function measureVideoStream({ durationMs = 4500, maxFrames = 8 } = {}) {
  if (!state.streamToken) throw new Error('Stream token yok');
  const startedAt = performance.now();
  const response = await fetch(`/video?streamToken=${encodeURIComponent(state.streamToken)}&health=${Date.now()}`, {
    cache: 'no-store',
    headers: { accept: 'multipart/x-mixed-replace' }
  });
  if (!response.body) throw new Error('Tarayıcı stream body vermedi');
  const reader = response.body.getReader();
  let buffer = new Uint8Array(0);
  let networkBytes = 0;
  let decodeFailures = 0;
  const frames = [];
  const frameTimes = [];
  const deadline = startedAt + durationMs;
  try {
    while (performance.now() < deadline && frames.length < maxFrames) {
      const timeoutMs = Math.max(80, Math.min(500, deadline - performance.now()));
      const read = await readWithTimeout(reader, timeoutMs);
      if (read.timeout) continue;
      if (read.done) break;
      networkBytes += read.value.length;
      buffer = appendBytes(buffer, read.value);
      while (true) {
        const start = findMarker(buffer, 0xff, 0xd8);
        if (start < 0) {
          if (buffer.length > 262144) buffer = buffer.slice(-2048);
          break;
        }
        const end = findMarker(buffer, 0xff, 0xd9, start + 2);
        if (end < 0) {
          if (start > 0) buffer = buffer.slice(start);
          break;
        }
        const jpeg = buffer.slice(start, end + 2);
        buffer = buffer.slice(end + 2);
        const frameAt = performance.now();
        frameTimes.push(frameAt);
        try {
          const decoded = await decodeJpegFrame(jpeg);
          frames.push(Object.assign({
            atMs: Math.round(frameAt - startedAt),
            bytes: jpeg.length
          }, decoded));
        } catch (error) {
          decodeFailures++;
          frames.push({
            atMs: Math.round(frameAt - startedAt),
            bytes: jpeg.length,
            decoded: false,
            error: error.message
          });
        }
        if (frames.length >= maxFrames) break;
      }
    }
  } finally {
    try { await reader.cancel(); } catch (_) {}
  }
  const gaps = [];
  for (let index = 1; index < frameTimes.length; index++) {
    gaps.push(Math.round(frameTimes[index] - frameTimes[index - 1]));
  }
  const decodedFrames = frames.filter((frame) => frame.decoded);
  const maxInterFrameGapMs = gaps.length ? Math.max(...gaps) : null;
  const allDecodedFramesLookFlat = decodedFrames.length > 0 && decodedFrames.every((frame) => frame.contrast < 3 && frame.lumaStdDev < 2);
  return {
    ok: response.ok && decodedFrames.length >= 1 && frames.length >= 2 && (maxInterFrameGapMs == null || maxInterFrameGapMs <= 2500),
    httpStatus: response.status,
    frames: frames.length,
    decodedFrames: decodedFrames.length,
    decodeFailures,
    networkBytes,
    averageJpegBytes: frames.length ? Math.round(frames.reduce((sum, frame) => sum + frame.bytes, 0) / frames.length) : 0,
    maxInterFrameGapMs,
    warning: allDecodedFramesLookFlat ? 'decoded frames look visually flat' : null,
    samples: frames.slice(0, 4)
  };
}
function readAscii(bytes, offset, length) {
  return String.fromCharCode(...bytes.slice(offset, offset + length));
}
function parseWavHeader(bytes) {
  if (bytes.length < 44) return { valid: false, error: 'short header' };
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const valid = readAscii(bytes, 0, 4) === 'RIFF' && readAscii(bytes, 8, 4) === 'WAVE';
  return {
    valid,
    sampleRate: view.getUint32(24, true),
    channels: view.getUint16(22, true),
    bitsPerSample: view.getUint16(34, true),
    dataOffset: 44,
    dataSize: view.getUint32(40, true)
  };
}
function analyzePcm16le(bytes, { sampleRate = 16000, channels = 1 } = {}) {
  const sampleCount = Math.floor(bytes.length / 2);
  if (sampleCount <= 0) {
    return { sampleCount: 0, durationMs: 0, rms: 0, peak: 0, estimatedHz: null };
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let peak = 0;
  let sumSquares = 0;
  let zeroCrossings = 0;
  let previousSign = 0;
  for (let index = 0; index < sampleCount; index++) {
    const sample = view.getInt16(index * 2, true);
    const absolute = Math.abs(sample);
    peak = Math.max(peak, absolute);
    const normalized = sample / 32768;
    sumSquares += normalized * normalized;
    const sign = sample > 0 ? 1 : sample < 0 ? -1 : previousSign;
    if (previousSign !== 0 && sign !== 0 && sign !== previousSign) zeroCrossings++;
    if (sign !== 0) previousSign = sign;
  }
  const frames = sampleCount / Math.max(1, channels);
  return {
    sampleCount,
    durationMs: Math.round(frames / sampleRate * 1000),
    rms: Number(Math.sqrt(sumSquares / sampleCount).toFixed(4)),
    peak: Number((peak / 32768).toFixed(4)),
    estimatedHz: zeroCrossings > 0 ? Math.round((zeroCrossings * sampleRate) / (2 * sampleCount)) : null
  };
}
async function measureAudioStream({ durationMs = 3000, minBodyBytes = 4096 } = {}) {
  if (!state.streamToken) throw new Error('Stream token yok');
  const startedAt = performance.now();
  const response = await fetch(`/audio?streamToken=${encodeURIComponent(state.streamToken)}&health=${Date.now()}`, {
    cache: 'no-store',
    headers: { accept: 'audio/wav' }
  });
  if (!response.body) throw new Error('Tarayıcı audio body vermedi');
  const reader = response.body.getReader();
  const chunks = [];
  let totalBytes = 0;
  const readTimes = [];
  const deadline = startedAt + durationMs;
  try {
    while (performance.now() < deadline || totalBytes < 44 + minBodyBytes) {
      const read = await readWithTimeout(reader, 500);
      if (read.timeout) {
        if (performance.now() >= deadline) break;
        continue;
      }
      if (read.done) break;
      chunks.push(read.value);
      totalBytes += read.value.length;
      readTimes.push(performance.now());
      if (performance.now() >= deadline && totalBytes >= 44 + minBodyBytes) break;
    }
  } finally {
    try { await reader.cancel(); } catch (_) {}
  }
  const bytes = concatChunks(chunks, totalBytes);
  const wav = parseWavHeader(bytes);
  const pcm = bytes.length > wav.dataOffset ? bytes.slice(wav.dataOffset) : new Uint8Array(0);
  const stats = analyzePcm16le(pcm, {
    sampleRate: wav.sampleRate || 16000,
    channels: wav.channels || 1
  });
  const gaps = [];
  for (let index = 1; index < readTimes.length; index++) {
    gaps.push(Math.round(readTimes[index] - readTimes[index - 1]));
  }
  const maxChunkGapMs = gaps.length ? Math.max(...gaps) : null;
  return {
    ok: response.ok && wav.valid && wav.bitsPerSample === 16 && pcm.length >= minBodyBytes && (maxChunkGapMs == null || maxChunkGapMs <= 1200),
    httpStatus: response.status,
    wav,
    chunks: chunks.length,
    totalBytes,
    pcmBytes: pcm.length,
    maxChunkGapMs,
    stats,
    warning: stats.rms < 0.001 ? 'live audio is near silence' : null
  };
}
async function measureTone() {
  const response = await fetch('/test/audio-tone?durationMs=1200&frequencyHz=880&amplitude=0.45', {
    cache: 'no-store',
    headers: { authorization: `Bearer ${state.token}` }
  });
  const bytes = new Uint8Array(await response.arrayBuffer());
  const wav = parseWavHeader(bytes);
  const pcm = bytes.slice(wav.dataOffset || 44);
  const stats = analyzePcm16le(pcm, {
    sampleRate: wav.sampleRate || 16000,
    channels: wav.channels || 1
  });
  return {
    ok: response.ok && wav.valid && stats.rms > 0.05 && stats.peak > 0.1 && Math.abs((stats.estimatedHz || 0) - 880) <= 80,
    httpStatus: response.status,
    wav,
    stats
  };
}
async function reportBrowserQuality({ video, audio, alert }) {
  const statusStartedAt = performance.now();
  try { await fetchJson('/status', { method: 'GET' }); } catch (_) {}
  const rttMs = Math.round(performance.now() - statusStartedAt);
  const failures = [video.ok, audio.ok, alert.ok].filter((ok) => !ok).length;
  const videoGapMs = video.maxInterFrameGapMs ?? (video.ok ? 0 : 5000);
  const audioGapMs = audio.maxChunkGapMs ?? (audio.ok ? 0 : 2000);
  const networkTier = failures >= 2
      ? 'critical'
      : failures === 1 || videoGapMs >= 2000 || audioGapMs >= 1000 || (alert.latencyMs || 0) >= 1500
        ? 'weak'
        : 'excellent';
  return fetchJson('/quality/report', {
    method: 'POST',
    body: JSON.stringify({
      clientId: state.clientId,
      tier: networkTier,
      networkTier,
      rttMs,
      consecutiveFailures: failures,
      videoFrameGapMs: videoGapMs,
      audioGapMs,
      skippedFrames: 0,
      skippedVideoFrames: video.ok ? 0 : 1,
      skippedAudioChunks: audio.ok ? 0 : 1,
      wsDisconnectCount: alert.ok ? 0 : 1,
      reconnectCount: 0,
      streamTimedOut: !video.ok,
      audioUnderrun: !audio.ok,
      watchActive: true,
      recentlyReconnected: false,
      createdAtMs: Date.now()
    })
  });
}
async function runFullHealthTest() {
  setText('fullState', 'çalışıyor');
  $('healthReport').textContent = '';
  const startedAtMs = Date.now();
  try {
    await ensurePair();
    const resetResult = await resetServerTestState();
    const startResult = await fetchJson('/test/start', { method: 'POST', body: '{}' });
    await startLive();
    const wsReady = await openEvents();
    const probe = await runProbe();
    const video = await measureVideoStream();
    setText('videoState', video.ok ? `${video.frames} frame` : 'sorun var');
    const audio = await measureAudioStream();
    setText('audioState', audio.ok ? `${audio.pcmBytes} PCM` : 'sorun var');
    const tone = await measureTone();
    const alert = await sendAlert(`MimiCam tam sağlık bildirimi ${new Date().toLocaleTimeString()}`);
    const qualityReport = await reportBrowserQuality({ video, audio, alert });
    await sleep(700);
    const serverStatus = await refreshStatus();
    const ok = !!wsReady && probe.ok === true && video.ok && audio.ok && tone.ok && alert.ok;
    const report = {
      ok,
      startedAtMs,
      durationMs: Date.now() - startedAtMs,
      resetResult,
      startResult,
      wsReady,
      probe: { ok: probe.ok, checks: probe.checks },
      video,
      audio,
      tone,
      alert,
      qualityReport,
      serverStatus
    };
    $('healthReport').textContent = JSON.stringify(report, null, 2);
    setText('fullState', ok ? 'sağlıklı' : 'sorun var');
    log('Tam sağlık testi tamam', { ok, video: video.ok, audio: audio.ok, tone: tone.ok, alert: alert.ok });
    return report;
  } catch (error) {
    const report = {
      ok: false,
      startedAtMs,
      durationMs: Date.now() - startedAtMs,
      error: error.message || String(error)
    };
    $('healthReport').textContent = JSON.stringify(report, null, 2);
    setText('fullState', 'sorun var');
    log('Tam sağlık testi hata verdi', report);
    return report;
  }
}
for (const [id, fn] of [['start', startLive], ['tone', playTone], ['alert', sendAlert], ['probe', runProbe], ['health', runFullHealthTest]]) {
  $(id).addEventListener('click', () => fn().catch((error) => log('Hata', { error: error.message })));
}
