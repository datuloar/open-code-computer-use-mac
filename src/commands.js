import { ToolError } from './tool-error.js';

const string = { type: 'string', minLength: 1, maxLength: 2000 };
const coordinate = { type: 'number', minimum: -32767, maximum: 32767 };
const target = { pid: { type: 'integer', minimum: 1, maximum: 2147483647 }, window: string };
const role = { role: { type: 'string', pattern: '^AX[A-Za-z]+$', maxLength: 60 } };
const point = { x: coordinate, y: coordinate };
const region = { ...point, width: { type: 'number', minimum: 1, maximum: 8192 }, height: { type: 'number', minimum: 1, maximum: 8192 } };
const schema = (properties, required = []) => ({ type: 'object', properties, required, additionalProperties: false });
const tool = (name, description, properties, required = [], gated = false) => ({ name, description, inputSchema: schema(properties, required), gated });

export const TOOLS = [
  tool('windows', 'List visible macOS windows with pid, title and bounds in screen points.', {}),
  tool('ui_tree', 'Read a bounded Accessibility tree. Prefer an observed pid or window title.', { ...target, depth: { type: 'integer', minimum: 1, maximum: 14 } }),
  tool('find', 'Find controls by label or identifier. Details reads one control value; secure fields stay hidden.', { ...target, ...role, text: string, details: { type: 'boolean' }, max_chars: { type: 'integer', minimum: 1, maximum: 2000 } }, ['text']),
  tool('tap', 'Click a uniquely named visible control. Ambiguous, disabled or covered controls refuse input.', { ...target, ...role, text: string }, ['text'], true),
  tool('focus', 'Bring the selected window forward without resizing it. Restores minimized windows.', target, [], true),
  tool('screenshot', 'Capture the primary display or a crop. Image pixels map 1:1 to screen points, including Retina.', region),
  tool('read_text', 'Read a screen crop with Apple Vision OCR. Returns text, confidence and screen-point bounds.', { ...region, language: string }),
  tool('click', 'Click an observed screen point on the primary display.', { ...point, button: { type: 'string', enum: ['left', 'right', 'middle', 'double', 'triple'] } }, ['x', 'y'], true),
  tool('move', 'Move the real pointer to an observed screen point.', point, ['x', 'y'], true),
  tool('drag', 'Drag between observed screen points; both endpoints are validated before pressing.', { ...point, to_x: coordinate, to_y: coordinate }, ['x', 'y', 'to_x', 'to_y'], true),
  tool('scroll', 'Scroll at the pointer or supplied point. Positive is up/left; negative is down/right.', { ...point, notches: { type: 'integer', minimum: -100, maximum: 100 }, horizontal: { type: 'boolean' } }, ['notches'], true),
  tool('type', 'Type Unicode text without the clipboard. Newlines send Return and tabs send Tab; verify the result.', { text: string }, ['text'], true),
  tool('press', 'Press keys such as cmd+a, option+left, ctrl+tab or Return. Modifiers always release.', { keys: string }, ['keys'], true),
  tool('wait', 'Delay up to 30 seconds, or poll one named control until it exists or is enabled without input.', { ...target, ...role, seconds: { type: 'number', minimum: 0, maximum: 30 }, text: string, state: { type: 'string', enum: ['exists', 'enabled'] } }, ['seconds']),
  tool('indicator', 'Start, stop or inspect desktop control. Human Escape requires manual resume; do not bypass it.', { action: { type: 'string', enum: ['start', 'stop', 'status'] } }, ['action']),
];

export function validate(name, input = {}) {
  const entry = TOOLS.find(t => t.name === name);
  if (!entry) throw new ToolError(`unknown tool: ${name}`);
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new ToolError('arguments must be an object');
  for (const key of entry.inputSchema.required) if (input[key] === undefined) throw new ToolError(`${key} is required`);
  for (const [key, value] of Object.entries(input)) {
    const rule = entry.inputSchema.properties[key];
    if (!rule) throw new ToolError(`unknown argument: ${key}`);
    if (rule.type === 'number' || rule.type === 'integer') {
      if (typeof value !== 'number' || !Number.isFinite(value) || (rule.type === 'integer' && !Number.isInteger(value))) throw new ToolError(`${key} must be a finite ${rule.type}`);
      if (value < rule.minimum || value > rule.maximum) throw new ToolError(`${key} is outside its supported range`);
    } else if (typeof value !== rule.type) throw new ToolError(`${key} must be a ${rule.type}`);
    if (rule.type === 'string' && (!value.length || value.length > (rule.maxLength ?? 2000))) throw new ToolError(`${key} must contain 1 to ${rule.maxLength ?? 2000} characters`);
    if (rule.pattern && !new RegExp(rule.pattern).test(value)) throw new ToolError(`${key} must be an observed Accessibility role such as AXButton`);
    if (rule.enum && !rule.enum.includes(value)) throw new ToolError(`${key} must be ${rule.enum.join(', ')}`);
  }
  if (input.pid !== undefined && input.window !== undefined) throw new ToolError('use pid or window, not both');
  if (name === 'focus' && input.pid === undefined && input.window === undefined) throw new ToolError('focus requires pid or window');
  if (['screenshot', 'read_text'].includes(name)) {
    const count = ['x', 'y', 'width', 'height'].filter(k => input[k] !== undefined).length;
    if (count !== 0 && count !== 4) throw new ToolError('a crop requires x, y, width and height');
  }
  if (name === 'scroll' && (!input.notches || (input.x === undefined) !== (input.y === undefined))) throw new ToolError('scroll requires nonzero notches and both x/y or neither');
  if (name === 'find' && input.max_chars !== undefined && !input.details) throw new ToolError('max_chars requires details');
  if (name === 'wait') {
    if (input.text !== undefined && input.seconds <= 0) throw new ToolError('a conditional wait requires positive seconds');
    if (input.text === undefined && ['pid', 'window', 'role', 'state'].some(k => input[k] !== undefined)) throw new ToolError('a conditional wait requires text');
  }
  return entry;
}
