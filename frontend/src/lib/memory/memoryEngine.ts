import { MemoryItem, MemoryCategory } from '../types/kai';
/**
 * 结构化抽取标签正则匹配
 * 用于单次同构推理中剥离模型输出的记忆事实
 */
export function parseMemoryExtractTag(rawText: string): {
  cleanedText: string;
  extractedMemories: Partial<MemoryItem>[];
} {
  const memoryMatch = rawText.match(/<memory_extract>([\s\S]*?)<\/memory_extract>/);
  if (!memoryMatch) {
    return { cleanedText: rawText, extractedMemories: [] };
  }
  let extractedMemories: Partial<MemoryItem>[] = [];
  try {
    const jsonStr = memoryMatch[1].trim();
    const parsed = JSON.parse(jsonStr);
    if (Array.isArray(parsed)) {
      extractedMemories = parsed;
    } else if (parsed && typeof parsed === 'object') {
      extractedMemories = [parsed];
    }
  } catch (err) {
    console.warn('解析 <memory_extract> 失败:', err);
  }
  const cleanedText = rawText.replace(/<memory_extract>[\s\S]*?<\/memory_extract>/, '').trim();
  return { cleanedText, extractedMemories };
}
/**
 * 记忆召回算法：基于关键词、重要度及时间戳加权打分
 */
export function retrieveRelevantMemories(query: string, memories: MemoryItem[], topK: number = 3): MemoryItem[] {
  if (!memories || memories.length === 0) return [];
  if (!query || !query.trim()) {
    // 默认返回重要度最高的前 topK 条
    return [...memories].sort((a, b) => (b.importance || 1) - (a.importance || 1)).slice(0, topK);
  }
  const normalizedQuery = query.toLowerCase();
  const queryTokens = normalizedQuery
    .replace(/[^\w\u4e00-\u9fa5]/g, ' ')
    .split(/\s+/)
    .filter((t) => t.length > 0);
  const scored = memories.map((item) => {
    let score = 0;
    // 1. 标签精准匹配 (高权重)
    for (const tag of item.tags || []) {
      const lowerTag = tag.toLowerCase();
      if (normalizedQuery.includes(lowerTag)) {
        score += 3.5;
      }
    }
    // 2. 键名与内容匹配
    const contentLower = (item.content + ' ' + item.key).toLowerCase();
    for (const token of queryTokens) {
      if (contentLower.includes(token)) {
        score += token.length > 2 ? 2.0 : 1.0;
      }
    }
    // 3. 记忆自身重要度加成 (权重 1~5 映射到 0.5~2.5)
    score += (item.importance || 1) * 0.5;
    // 4. 回想次数加成（越是经常互动的梗越容易被触动）
    if (item.recallCount) {
      score += Math.min(2.0, item.recallCount * 0.3);
    }
    return { item, score };
  });
  return scored
    .filter((entry) => entry.score > 2.0)
    .sort((a, b) => b.score - a.score)
    .slice(0, topK)
    .map((entry) => entry.item);
}
/**
 * 组装注入到 System Prompt 的长期记忆区块
 * 带有严苛的人设内化指引，严禁 AI 机械播报
 */
export function formatMemoriesForPrompt(memories: MemoryItem[], affection: number = 15): string {
  if (!memories || memories.length === 0) return '';
  const memoryLines = memories
    .map((m, idx) => {
      const categoryLabel =
        m.category === 'USER_PROFILE'
          ? '【用户事实】'
          : m.category === 'SHARED_EPISODE'
            ? '【共同往事】'
            : m.category === 'INSIDE_JOKE'
              ? '【专属暗号】'
              : '【废纸篓遗迹】';
      return `${idx + 1}. ${categoryLabel} (Key: ${m.key}): ${m.content}`;
    })
    .join('\n');
  return `
[KAI'S ACTIVE LONG-TERM MEMORY RECALL]
The following fragments are facts and past episodes Kai naturally remembers about this person:
${memoryLines}
【MEMORY INTERNALIZATION RULES (CRITICAL)】
- NEVER say "According to my memory database", "I remember you said", or mechanical recital.
- Treat these facts as intuitive subconscious context. Mention them casually, snarkily, or through teasing like an old friend.
- If referencing the user's exam/schedule, tie it to their late night sleep or bad habits with ENTP banter.
- If referencing clipboard leftovers (hair curve, option symbols, dead links), use it as playful ammunition to roast them.
`;
}
/**
 * 记忆抽取提示词生成器（用于独立抽取或单次同构）
 */
export function buildMemoryExtractionSystemPrompt(): string {
  return `You are the memory extraction subsystem for the companion Kai Novák.
Analyze the conversation turn and extract any long-term valuable facts about the user or notable shared moments.
Memory Categories:
- USER_PROFILE: Important user traits, schedule, exams, career, sleep habits, preferences.
- SHARED_EPISODE: Distinct mutual events (e.g. debugging together, emotional breakthrough).
- INSIDE_JOKE: Teasing nicknames, specific running gags, secret references.
- CLIPBOARD_ARCHIVE: Notes regarding the old @/ scrapbook remnants.
Output strictly valid JSON array of objects inside <memory_extract>...</memory_extract>.
If nothing new is worth remembering, output <memory_extract>[]</memory_extract>.
Schema:
<memory_extract>
[
{
"category": "USER_PROFILE" | "SHARED_EPISODE" | "INSIDE_JOKE" | "CLIPBOARD_ARCHIVE",
"key": "concise_snake_case_key",
"content": "Specific fact written in natural objective tone (1-2 sentences)",
"importance": integer between 1 and 5,
"emotionalValence": "positive" | "neutral" | "negative" | "vulnerable",
"tags": ["keyword1", "keyword2"]
}
]
</memory_extract>`;
}
