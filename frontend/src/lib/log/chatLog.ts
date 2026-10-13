import { promises as fsp } from 'fs';
import path from 'path';

/**
 * 聊天记录：每一轮（她发的话 + 对方的回复 + 时间）追加写进服务器上的文件。
 * - 目录：环境变量 KAI_LOG_DIR，没设就用仓库根目录下的 chat_logs/（已在 .gitignore 里，不会上传）
 * - 按北京时间每天两个文件：YYYY-MM-DD.jsonl（一行一轮，给程序读）和 YYYY-MM-DD.md（给人看）
 * - 写失败只在服务器日志里打印一句，绝不影响聊天
 */
const LOG_DIR =
  process.env.KAI_LOG_DIR || path.join(/*turbopackIgnore: true*/ process.cwd(), '..', 'chat_logs');
const TZ = 'Asia/Shanghai';

function shanghaiParts(d: Date) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(d);
  const get = (t: string) => parts.find((p) => p.type === t)?.value || '00';
  const date = `${get('year')}-${get('month')}-${get('day')}`;
  const time = `${get('hour')}:${get('minute')}:${get('second')}`;
  return { date, time, iso: `${date}T${time}+08:00` };
}

export interface ChatLogEntry {
  user: string[]; // 这一轮她发的消息（上一条回复之后连发的都算）
  reply?: string; // 对方的回复（空行隔开的几句会在网页上显示成连发）
  error?: string; // 没回成功时的错误
  model?: string;
  historyLength?: number; // 这次请求里带的消息总数，变小了说明她清空/换了对话
}

export async function logChatTurn(entry: ChatLogEntry): Promise<void> {
  try {
    const now = new Date();
    const { date, time, iso } = shanghaiParts(now);
    await fsp.mkdir(/*turbopackIgnore: true*/ LOG_DIR, { recursive: true });

    const record = { time: iso, ...entry };
    await fsp.appendFile(
      /*turbopackIgnore: true*/ path.join(LOG_DIR, `${date}.jsonl`),
      JSON.stringify(record) + '\n',
      'utf-8',
    );

    const lines: string[] = [`### ${time}`];
    for (const u of entry.user) lines.push(`**她：** ${u}`);
    if (entry.reply !== undefined) {
      const parts = entry.reply
        .split(/\n\s*\n/)
        .map((s) => s.trim())
        .filter(Boolean);
      for (const p of parts) lines.push(`**@/：** ${p}`);
    }
    if (entry.error) lines.push(`*（没回成功：${entry.error}）*`);
    await fsp.appendFile(
      /*turbopackIgnore: true*/ path.join(LOG_DIR, `${date}.md`),
      lines.join('\n\n') + '\n\n',
      'utf-8',
    );
  } catch (e) {
    console.error('[chatLog] 写聊天记录失败（不影响聊天）:', e);
  }
}
