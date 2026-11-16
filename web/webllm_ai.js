let _dentalWebEngine = null;
let _dentalWebModel = '';

async function _loadWebLLM() {
  if (window.webllm) return window.webllm;
  try {
    const mod = await import('https://esm.run/@mlc-ai/web-llm');
    window.webllm = mod;
    return mod;
  } catch (e) {
    const mod = await import('https://cdn.jsdelivr.net/npm/@mlc-ai/web-llm/+esm');
    window.webllm = mod;
    return mod;
  }
}

window.dentalWebAiInit = async function(modelId, onProgress) {
  try {
    if (!navigator.gpu) {
      throw new Error('WebGPU not available. Use Chrome/Edge with hardware acceleration (secure context).');
    }
    const webllm = await _loadWebLLM();
    _dentalWebModel = modelId || 'Llama-3.2-1B-Instruct-q4f16_1-MLC';
    const initProgressCallback = (report) => {
      try {
        if (typeof onProgress === 'function') {
          const text = (report && (report.text || (typeof report.progress === 'number' ? ('Loading: ' + Math.round(report.progress * 100) + '%') : ''))) || String(report || '');
          onProgress(text);
        }
      } catch (e) {
        console.warn('progress callback error', e);
      }
    };
    initProgressCallback({ text: 'Loading WebLLM engine...' });
    _dentalWebEngine = await webllm.CreateMLCEngine(_dentalWebModel, { initProgressCallback });
    initProgressCallback({ text: 'Finalizing model load...' });
    try {
      await _dentalWebEngine.reload(_dentalWebModel);
    } catch (e) {
      console.warn('reload after init skipped/failed', e);
    }
    initProgressCallback({ text: 'Model ready' });
    return 'ready: ' + _dentalWebModel;
  } catch (e) {
    console.error('dentalWebAiInit error', e);
    const msg = (e && e.message) ? e.message : String(e);
    throw new Error(msg);
  }
};

window.dentalWebAiGenerate = async function(prompt, maxTokens) {
  if (!_dentalWebEngine) throw new Error('Web AI not initialized');
  const req = {
    messages: [{ role: 'user', content: prompt }],
    temperature: 0.1,
    max_tokens: maxTokens || 512,
  };
  try {
    const reply = await _dentalWebEngine.chat.completions.create(req);
    return (reply.choices && reply.choices[0] && reply.choices[0].message && reply.choices[0].message.content) || '';
  } catch (e) {
    const msg = (e && e.message) ? e.message : String(e);
    if (/Model not loaded/i.test(msg) && _dentalWebModel) {
      await _dentalWebEngine.reload(_dentalWebModel);
      const reply = await _dentalWebEngine.chat.completions.create(req);
      return (reply.choices && reply.choices[0] && reply.choices[0].message && reply.choices[0].message.content) || '';
    }
    throw e;
  }
};

window.dentalWebAiReady = function() { return !!_dentalWebEngine; };
window.dentalWebAiModelName = function() { return _dentalWebModel || 'WebLLM'; };
