// Defaults to "n8n on the same host as this page, port 5678" so the simulator
// works unmodified whether it's opened on localhost or on a remote Docker host.
// Override by setting window.SWIFTDROP_WEBHOOK_URL before this script loads.
const WEBHOOK_URL =
  window.SWIFTDROP_WEBHOOK_URL ||
  `${window.location.protocol}//${window.location.hostname}:5678/webhook/whatsapp`;
const STORAGE_KEY = 'swiftdrop_sim_chats';

const messagesEl = document.getElementById('messages');
const phoneInput = document.getElementById('phoneInput');
const messageInput = document.getElementById('messageInput');
const sendBtn = document.getElementById('sendBtn');
const newCustomerBtn = document.getElementById('newCustomerBtn');
const typingIndicator = document.getElementById('typingIndicator');
const connBanner = document.getElementById('connBanner');
const statusEl = document.getElementById('status');

function loadChats() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
  } catch (e) {
    return {};
  }
}

function saveChats(chats) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(chats));
  } catch (e) {
    // ignore storage failures (private browsing, quota, etc.)
  }
}

function currentPhone() {
  return phoneInput.value.trim();
}

function formatTime(date) {
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function renderMessages() {
  const chats = loadChats();
  const history = chats[currentPhone()] || [];
  messagesEl.innerHTML = '';
  for (const msg of history) {
    appendBubble(msg.direction, msg.text, msg.time, false);
  }
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

function appendBubble(direction, text, time, persist = true) {
  const row = document.createElement('div');
  row.className = `bubble-row ${direction}`;

  const bubble = document.createElement('div');
  bubble.className = `bubble ${direction}`;
  bubble.textContent = text;

  if (direction !== 'system') {
    const meta = document.createElement('div');
    meta.className = 'meta';
    meta.textContent = time || formatTime(new Date());
    bubble.appendChild(meta);
  }

  row.appendChild(bubble);
  messagesEl.appendChild(row);
  messagesEl.scrollTop = messagesEl.scrollHeight;

  if (persist) {
    const chats = loadChats();
    const phone = currentPhone();
    if (!chats[phone]) chats[phone] = [];
    chats[phone].push({ direction, text, time: time || formatTime(new Date()) });
    saveChats(chats);
  }
}

function genMessageId() {
  if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
  return 'msg-' + Date.now() + '-' + Math.random().toString(36).slice(2, 10);
}

function genRandomPhone() {
  const n = Math.floor(10000000 + Math.random() * 89999999);
  return '080' + n;
}

async function sendMessage(text) {
  const phone = currentPhone();
  if (!phone) {
    alert('Enter a simulated customer phone number first.');
    return;
  }

  appendBubble('out', text);
  messageInput.value = '';
  sendBtn.disabled = true;
  typingIndicator.style.visibility = 'visible';
  connBanner.classList.remove('show');

  const payload = {
    phone,
    message: text,
    message_id: genMessageId(),
    timestamp: new Date().toISOString()
  };

  try {
    const res = await fetch(WEBHOOK_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    const data = await res.json().catch(() => ({}));

    if (!res.ok) {
      appendBubble(
        'system',
        data.error
          ? `⚠ ${data.error}${data.missing_fields ? ': ' + data.missing_fields.join(', ') : ''}`
          : `⚠ Request failed (HTTP ${res.status})`
      );
    } else if (data.reply) {
      appendBubble('in', data.reply);
    } else if (data.status === 'duplicate_ignored') {
      appendBubble('system', 'Duplicate message ignored by the server.');
    } else {
      appendBubble('system', `Received (intent: ${data.intent || 'unknown'}, no reply text returned).`);
    }
  } catch (err) {
    connBanner.classList.add('show');
    appendBubble('system', "⚠ Couldn't reach SwiftDrop (is n8n running?).");
  } finally {
    sendBtn.disabled = false;
    typingIndicator.style.visibility = 'hidden';
    messageInput.focus();
  }
}

sendBtn.addEventListener('click', () => {
  const text = messageInput.value.trim();
  if (text) sendMessage(text);
});

messageInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    e.preventDefault();
    const text = messageInput.value.trim();
    if (text) sendMessage(text);
  }
});

document.querySelectorAll('.quick-replies button').forEach((btn) => {
  btn.addEventListener('click', () => sendMessage(btn.dataset.msg));
});

newCustomerBtn.addEventListener('click', () => {
  phoneInput.value = genRandomPhone();
  renderMessages();
  messageInput.focus();
});

phoneInput.addEventListener('change', renderMessages);

renderMessages();
messageInput.focus();
