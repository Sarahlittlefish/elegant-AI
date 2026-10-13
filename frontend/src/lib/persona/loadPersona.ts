import fs from 'fs';
import path from 'path';

/**
 * 读取仓库根目录的 kai_persona_v2.md，原文照搬作为系统提示词。
 * 唯一的处理：去掉首尾空白，以及结尾的聊天指令「听懂回复ok」（如果有）。
 * 不缓存：改了 md 文件，下一条消息就生效。
 */
const CANDIDATE_PATHS = [
  path.join(process.cwd(), '..', 'kai_persona_v2.md'),
  path.join(process.cwd(), 'kai_persona_v2.md'),
];

export function loadKaiPersona(): string {
  for (const filePath of CANDIDATE_PATHS) {
    if (fs.existsSync(/*turbopackIgnore: true*/ filePath)) {
      const raw = fs.readFileSync(/*turbopackIgnore: true*/ filePath, 'utf-8').replace(/^\uFEFF/, '');
      return raw.trim().replace(/\s*听懂回复\s*ok\s*$/i, '').trim();
    }
  }
  throw new Error('找不到人设文件 kai_persona_v2.md');
}
