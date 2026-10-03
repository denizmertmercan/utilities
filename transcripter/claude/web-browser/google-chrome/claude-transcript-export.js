/**
 * Claude.ai conversation exporter (browser console utility).
 *
 * Origin: built for a long Claude.ai chat whose saved HTML/MHTML contained
 * only the currently mounted messages. The API URL was found in that page's
 * chat-tree preload script; it is private and can change without notice.
 * Run while signed in on a claude.ai /chat/<uuid> page: paste this entire file
 * into Chrome DevTools Console, press Enter, then call exportClaude().
 *
 *   exportClaude()                  -> API, falls back to DOM harvest
 *   exportClaude({ mode: 'dom' })   -> force the DOM harvester
 *   exportClaude({ mode: 'api' })   -> force the API, no fallback
 *   exportClaude({ format: 'md' })  -> 'md' | 'json' | 'both' (default)
 *   exportClaude({ expandTools: true })  -> DOM mode: click open collapsed blocks
 *
 * 'both' downloads three files on API success: .md is the active conversation's
 * user/Claude text (including progress updates) and uploaded filenames, with
 * no thinking or tool blocks from the API. .json is a simplified active-branch model;
 * -archive.json is the unmodified API response, including alternate branches,
 * tool data, and conversation metadata. None downloads uploaded file bytes or
 * separate artifact files. API failure falls back to scrolling the live DOM:
 * this may miss content or include rendered tool text, and there is no raw archive.
 * Files go to Chrome's configured download location, not beside this script:
 * pasted code cannot infer its own disk path. Chrome may ask permission for
 * multiple downloads. Outputs can include private conversation text and tool
 * inputs; review before sharing them.
 * The function returns the simplified model for inspection in the console.
 */
(() => {
  'use strict';

  const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';

  // ---------------------------------------------------------------- utilities

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const nextFrame = () => new Promise((r) => requestAnimationFrame(() => r()));

  function cookie(name) {
    const prefix = name + '=';
    for (const part of document.cookie.split(';')) {
      const trimmed = part.trim();
      if (trimmed.startsWith(prefix)) {
        try {
          return decodeURIComponent(trimmed.slice(prefix.length));
        } catch {
          return trimmed.slice(prefix.length);
        }
      }
    }
    return undefined;
  }

  function conversationIds() {
    const match = new RegExp(`/chat/(${UUID})`, 'i').exec(location.pathname);
    if (!match) throw new Error('Not on a /chat/<uuid> page.');
    // The page's own preload uses this cookie to address the organization API.
    const org = cookie('lastActiveOrg');
    if (!org || !new RegExp(`^${UUID}$`, 'i').test(org)) {
      throw new Error('No usable lastActiveOrg cookie; use { mode: "dom" }.');
    }
    return { org, conversation: match[1] };
  }

  function slugify(text, fallback) {
    const slug = (text || '')
      .toLowerCase()
      .replace(/[^\p{L}\p{N}]+/gu, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 80);
    return slug || fallback;
  }

  function download(filename, text, mime) {
    const url = URL.createObjectURL(new Blob([text], { type: `${mime};charset=utf-8` }));
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10_000);
  }

  // -------------------------------------------------------------- API capture

  async function fetchConversation({ org, conversation }) {
    // Request the complete tree and tool blocks; the Markdown filter runs later.
    const params = new URLSearchParams({
      tree: 'True',
      rendering_mode: 'messages',
      render_all_tools: 'true',
    });
    const url = `/api/organizations/${org}/chat_conversations/${conversation}?${params}`;
    const response = await fetch(url, {
      credentials: 'include',
      headers: { 'anthropic-client-platform': 'web_claude_ai' },
    });
    if (!response.ok) throw new Error(`API responded ${response.status} for ${url}`);
    return response.json();
  }

  /**
   * Tree mode returns every branch. Walk parent links up from the active leaf so
   * the export matches the thread actually displayed, then reverse to reading order.
   */
  function activeBranch(messages, leafUuid) {
    const byUuid = new Map(messages.map((m) => [m.uuid, m]));
    if (!leafUuid || !byUuid.has(leafUuid)) return messages;

    const chain = [];
    const seen = new Set();
    let cursor = byUuid.get(leafUuid);
    while (cursor && !seen.has(cursor.uuid)) {
      seen.add(cursor.uuid);
      chain.push(cursor);
      cursor = byUuid.get(cursor.parent_message_uuid);
    }
    return chain.reverse();
  }

  function normalizeBlock(block) {
    // The readable model is intentionally selective; the archive retains every field.
    const type = block?.type ?? 'text';
    switch (type) {
      case 'text':
      case 'thinking':
        return { type, text: block.text ?? block.thinking ?? '' };
      case 'tool_use':
        return {
          type,
          name: block.name ?? 'tool',
          input: block.input ?? null,
          text: block.message ?? '',
        };
      case 'tool_result':
        return {
          type,
          name: block.name ?? 'tool',
          text: typeof block.content === 'string' ? block.content : '',
          content: block.content ?? null,
          isError: Boolean(block.is_error),
        };
      default:
        return { type, text: block.text ?? '', raw: block };
    }
  }

  function normalizeFromApi(payload) {
    const raw = payload.chat_messages ?? payload.messages ?? [];
    // Edited/retried messages may be in the tree but not in the displayed path.
    const ordered = activeBranch(raw, payload.current_leaf_message_uuid);

    const turns = ordered.map((message) => {
      const blocks = Array.isArray(message.content) && message.content.length
        ? message.content.map(normalizeBlock)
        : [{ type: 'text', text: message.text ?? '' }];

      return {
        uuid: message.uuid ?? null,
        parent: message.parent_message_uuid ?? null,
        role: message.sender === 'human' ? 'user' : 'assistant',
        createdAt: message.created_at ?? null,
        blocks,
        attachments: (message.attachments ?? []).map((a) => ({
          name: a.file_name ?? a.name ?? null,
          type: a.file_type ?? null,
          size: a.file_size ?? null,
        })),
        files: (message.files ?? []).map((f) => f.file_name ?? f.name ?? null),
      };
    });

    return {
      source: 'api',
      title: payload.name || document.title.replace(/\s*[-–]\s*Claude\s*$/, ''),
      url: location.href,
      conversationUuid: payload.uuid ?? null,
      model: payload.model ?? null,
      createdAt: payload.created_at ?? null,
      exportedAt: new Date().toISOString(),
      turns,
    };
  }

  // -------------------------------------------------------------- DOM capture

  const MESSAGE_SELECTOR = '[data-testid="user-message"],[data-testid="assistant-message"]';

  function scrollContainer() {
    let node = document.querySelector(MESSAGE_SELECTOR);
    while (node && node !== document.body) {
      const style = getComputedStyle(node);
      const scrolls = /auto|scroll/.test(style.overflowY);
      if (scrolls && node.scrollHeight > node.clientHeight + 40) return node;
      node = node.parentElement;
    }
    return document.scrollingElement || document.documentElement;
  }

  /**
   * Virtualized rows unmount as they leave the viewport, so DOM position is not a
   * stable ordering key. Absolute offset inside the scroll container is.
   */
  function absoluteOffset(element, container) {
    const isPage = container === document.scrollingElement || container === document.documentElement;
    const top = element.getBoundingClientRect().top;
    if (isPage) return top + window.scrollY;
    return top - container.getBoundingClientRect().top + container.scrollTop;
  }

  function turnKeyFor(element, role, markdown) {
    const keyed = element.closest('[data-turn-key]');
    if (keyed) return keyed.getAttribute('data-turn-key');
    // Older or differently rendered rows may lack the stable turn key.
    let hash = 0;
    for (let i = 0; i < markdown.length; i += 1) {
      hash = (hash * 31 + markdown.charCodeAt(i)) | 0;
    }
    return `${role}:${markdown.length}:${hash}`;
  }

  function expandCollapsed(root) {
    for (const toggle of root.querySelectorAll('[aria-expanded="false"]')) {
      if (toggle.closest('[data-cds="ChatComposer"]')) continue;
      if (toggle.getAttribute('aria-haspopup')) continue;
      try {
        toggle.click();
      } catch {
        /* a toggle that refuses to open is not worth aborting the export for */
      }
    }
  }

  function collect(store, container, expandTools) {
    for (const element of document.querySelectorAll(MESSAGE_SELECTOR)) {
      const role = element.getAttribute('data-testid') === 'user-message' ? 'user' : 'assistant';
      if (expandTools) expandCollapsed(element);

      const parts = [htmlToMarkdown(element).trim()];
      for (const block of shadowDiffBlocks(element)) {
        parts.push(fenceText(diffBlockText(block)));
      }
      const markdown = parts.filter(Boolean).join('\n\n');
      if (!markdown) continue;

      const key = turnKeyFor(element, role, markdown);
      const offset = absoluteOffset(element, container);
      const existing = store.get(key);

      // Keep the longest capture: a row re-mounted mid-scroll can be partly rendered.
      if (!existing || markdown.length > existing.markdown.length) {
        store.set(key, { key, role, markdown, offset });
      } else {
        existing.offset = offset;
      }
    }
  }

  function shadowDiffBlocks(root) {
    const blocks = [];

    function visit(node) {
      for (const child of node.children || []) {
        if (child.shadowRoot) {
          blocks.push(...child.shadowRoot.querySelectorAll('pre[data-file]'));
          visit(child.shadowRoot);
        }
        visit(child);
      }
    }

    visit(root);
    return blocks;
  }

  function diffBlockText(element) {
    const content = element.querySelector('[data-content]');
    if (!content) return element.textContent;

    return [...content.children]
      .filter((line) => line.hasAttribute('data-line'))
      .map((line) => {
        const type = line.getAttribute('data-line-type');
        const prefix = type === 'addition' ? '+' : type === 'deletion' ? '-' : '';
        return prefix + line.textContent;
      })
      .join('\n');
  }

  async function harvestFromDom({ expandTools = false, step = 0.7, settle = 260 } = {}) {
    const container = scrollContainer();
    const store = new Map();
    const restore = container.scrollTop;

    // Scrolling mounts new transcript rows and unmounts earlier ones.
    container.scrollTop = 0;
    await sleep(settle);

    let previous = -1;
    let stalled = 0;
    for (let guard = 0; guard < 2000; guard += 1) {
      collect(store, container, expandTools);

      if (container.scrollTop === previous) {
        stalled += 1;
        if (stalled > 2) break;
      } else {
        stalled = 0;
      }
      previous = container.scrollTop;

      if (container.scrollTop + container.clientHeight >= container.scrollHeight - 2) {
        collect(store, container, expandTools);
        break;
      }

      container.scrollTop += Math.max(200, container.clientHeight * step);
      await nextFrame();
      await sleep(settle);
    }

    container.scrollTop = restore;

    const turns = [...store.values()]
      .sort((a, b) => a.offset - b.offset)
      .map(({ key, role, markdown }) => ({
        uuid: new RegExp(`^(${UUID})`, 'i').test(key) ? RegExp.$1 : null,
        parent: null,
        role,
        createdAt: null,
        blocks: [{ type: 'text', text: markdown }],
        attachments: [],
        files: [],
      }));

    return {
      source: 'dom',
      title: document.title.replace(/\s*[-–]\s*Claude\s*$/, ''),
      url: location.href,
      conversationUuid: (new RegExp(`/chat/(${UUID})`, 'i').exec(location.pathname) || [])[1] ?? null,
      model: document.querySelector('[data-testid="model-selector-dropdown"]')?.textContent?.trim() ?? null,
      createdAt: null,
      exportedAt: new Date().toISOString(),
      turns,
    };
  }

  // ------------------------------------------------------- HTML -> Markdown

  const SKIP = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'SVG']);

  function isHidden(element) {
    if (element.getAttribute('aria-hidden') === 'true') return true;
    if (element.hasAttribute('hidden')) return true;
    return element.classList.contains('sr-only');
  }

  function inlineChildren(node) {
    let out = '';
    for (const child of node.childNodes) out += renderNode(child);
    return out;
  }

  function fence(element) {
    const language = (element.className.match(/language-([\w+#-]+)/) || [])[1] || '';
    return fenceText(element.textContent, language);
  }

  function fenceText(text, language = '') {
    const body = text.replace(/\n+$/, '');
    const ticks = '`'.repeat(Math.max(3, ...(body.match(/`{3,}/g) || ['']).map((m) => m.length + 1)));
    return `\n${ticks}${language}\n${body}\n${ticks}\n\n`;
  }

  function renderList(element, ordered) {
    let out = '\n';
    let index = Number(element.getAttribute('start') || 1);
    for (const item of element.children) {
      if (item.tagName !== 'LI') continue;
      const marker = ordered ? `${index++}. ` : '- ';
      const body = inlineChildren(item).trim().replace(/\n/g, '\n' + ' '.repeat(marker.length));
      out += `${marker}${body}\n`;
    }
    return out + '\n';
  }

  function renderTable(element) {
    const rows = [...element.querySelectorAll('tr')].map((row) =>
      [...row.children].map((cell) => inlineChildren(cell).trim().replace(/\|/g, '\\|')),
    );
    if (!rows.length) return '';
    const width = Math.max(...rows.map((r) => r.length));
    const line = (cells) => `| ${Array.from({ length: width }, (_, i) => cells[i] ?? '').join(' | ')} |`;
    const [head, ...body] = rows;
    return `\n${line(head)}\n| ${Array(width).fill('---').join(' | ')} |\n${body.map(line).join('\n')}\n\n`;
  }

  function renderNode(node) {
    if (node.nodeType === Node.TEXT_NODE) return node.nodeValue.replace(/\s+/g, ' ');
    if (node.nodeType !== Node.ELEMENT_NODE) return '';
    if (SKIP.has(node.tagName) || isHidden(node)) return '';

    switch (node.tagName) {
      case 'BR':
        return '  \n';
      case 'HR':
        return '\n---\n\n';
      case 'P':
        return `\n${inlineChildren(node).trim()}\n\n`;
      case 'H1':
      case 'H2':
      case 'H3':
      case 'H4':
      case 'H5':
      case 'H6':
        return `\n${'#'.repeat(Number(node.tagName[1]))} ${inlineChildren(node).trim()}\n\n`;
      case 'STRONG':
      case 'B':
        return `**${inlineChildren(node).trim()}**`;
      case 'EM':
      case 'I':
        return `*${inlineChildren(node).trim()}*`;
      case 'DEL':
      case 'S':
        return `~~${inlineChildren(node).trim()}~~`;
      case 'CODE':
        return node.closest('pre') ? node.textContent : `\`${node.textContent}\``;
      case 'PRE':
        return fence(node.querySelector('code') || node);
      case 'BLOCKQUOTE':
        return `\n${inlineChildren(node).trim().replace(/^/gm, '> ')}\n\n`;
      case 'UL':
        return renderList(node, false);
      case 'OL':
        return renderList(node, true);
      case 'TABLE':
        return renderTable(node);
      case 'A': {
        const label = inlineChildren(node).trim();
        const href = node.getAttribute('href');
        return href && !href.startsWith('#') ? `[${label}](${href})` : label;
      }
      case 'IMG': {
        const alt = node.getAttribute('alt') || 'image';
        const src = node.getAttribute('src') || '';
        return src.startsWith('data:') ? `![${alt}](embedded)` : `![${alt}](${src})`;
      }
      default:
        return inlineChildren(node);
    }
  }

  function htmlToMarkdown(element) {
    return inlineChildren(element)
      .replace(/[ \t]+\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  // ------------------------------------------------------------ MD rendering

  function renderBlock(block) {
    switch (block.type) {
      case 'thinking':
      case 'tool_use':
      case 'tool_result':
        return '';
      default:
        return (block.text ?? '').trim();
    }
  }

  function toMarkdown(model) {
    const meta = [
      `# ${model.title}`,
      '',
      `- **Source:** ${model.url}`,
      model.model ? `- **Model:** ${model.model}` : null,
      model.createdAt ? `- **Started:** ${model.createdAt}` : null,
      `- **Exported:** ${model.exportedAt} (via ${model.source})`,
      `- **Turns:** ${model.turns.length}`,
      '',
      '---',
      '',
    ].filter((line) => line !== null);

    const body = model.turns.map((turn) => {
      const heading = turn.role === 'user' ? '## User' : '## Claude';
      const stamp = turn.createdAt ? ` *(${turn.createdAt})*` : '';
      // API turns with empty text still get a heading; DOM mode cannot capture empty rows.
      const parts = turn.blocks.map(renderBlock).filter(Boolean);

      if (turn.attachments.length) {
        parts.push(`**Attachments:** ${turn.attachments.map((a) => a.name).filter(Boolean).join(', ')}`);
      }
      if (turn.files.length) {
        parts.push(`**Files:** ${turn.files.filter(Boolean).join(', ')}`);
      }
      return `${heading}${stamp}\n\n${parts.join('\n\n')}`;
    });

    return `${meta.join('\n')}${body.join('\n\n---\n\n')}\n`;
  }

  // ------------------------------------------------------------------- entry

  async function exportClaude({ mode = 'auto', format = 'both', expandTools = false } = {}) {
    let model;
    let archive;

    if (mode !== 'dom') {
      try {
        // Keep the raw response before normalization removes fields and branches.
        archive = await fetchConversation(conversationIds());
        model = normalizeFromApi(archive);
        if (!model.turns.length) throw new Error('API returned zero turns.');
      } catch (error) {
        if (mode === 'api') throw error;
        console.warn('[claude-export] API path failed, harvesting the DOM instead:', error.message);
      }
    }

    if (!model) {
      model = await harvestFromDom({ expandTools });
    }
    if (!model.turns.length) throw new Error('No turns captured.');

    const timestamp = model.exportedAt
      .replace(/[-:]/g, '')
      .replace('T', '-')
      .replace(/\.\d{3}Z$/, 'Z');
    const base = `claude-${slugify(model.title, model.conversationUuid || 'transcript')}-${timestamp}`;
    if (format === 'json' || format === 'both') {
      download(`${base}.json`, JSON.stringify(model, null, 2), 'application/json');
      if (archive) {
        download(`${base}-archive.json`, JSON.stringify(archive, null, 2), 'application/json');
      } else {
        console.warn('[claude-export] No API response to archive; DOM mode cannot provide raw JSON.');
      }
    }
    if (format === 'md' || format === 'both') {
      download(`${base}.md`, toMarkdown(model), 'text/markdown');
    }

    console.info(`[claude-export] ${model.turns.length} turns via ${model.source} -> ${base}`);
    return model;
  }

  window.exportClaude = exportClaude;
  console.info('[claude-export] ready — run exportClaude()');
})();
