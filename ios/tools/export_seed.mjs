// 把网页版的开场聊天记录（frontend/src/lib/data/seedHistory.ts）原样导出成 iPad app 用的 JSON。
// 用法（在仓库根目录）：node ios/tools/export_seed.mjs
import { writeFileSync } from 'node:fs';
const { SEED_HISTORY } = await import('../../frontend/src/lib/data/seedHistory.ts');
writeFileSync(new URL('../Kai/Resources/seed_history.json', import.meta.url), JSON.stringify(SEED_HISTORY, null, 2) + '\n');
console.log(`导出了 ${SEED_HISTORY.length} 条`);
