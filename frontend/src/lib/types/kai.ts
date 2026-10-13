export interface PersonaWeights {
  formality: number; // 0.0 (极度随意) ~ 1.0 (拘谨客套)
  sarcasm: number; // 0.0 (温和规矩) ~ 1.0 (极度嘴欠/反讽)
  brevity: number; // 0.0 (详尽长段) ~ 1.0 (极简碎句)
  affection: number; // 0.0 ~ 100.0 (动态好感与羁绊值)
  defensiveness: number; // 0.1 (信任开放) ~ 1.0 (冷漠警戒)
}
export interface MentalState {
  delta_affection: number;
  trigger_category:
    | "LINGUISTIC_BANTER"
    | "AUTHENTIC_VULNERABILITY"
    | "SPATIAL_AWARENESS"
    | "SPAM_PENALTY"
    | "SYCOPHANCY_REJECTION"
    | "GENERAL_INTERACTION"
    | "MEMORY_RECALL_POSITIVE"
    | "EVENT_RESONANCE";
  reason: string;
  defensiveness_change?: number;
}
export type MemoryCategory =
  | "USER_PROFILE" // 用户硬事实（时区、作息习惯、专业、考试、喜好）
  | "SHARED_EPISODE" // 共同经历的往事片段（某次熬夜、某次争论输赢、某次互诉心声）
  | "INSIDE_JOKE" // 专属黑话与梗（如 Blender 头发插件、发饰提取码、特蕾莎同款白眼）
  | "CLIPBOARD_ARCHIVE"; // 历史上在 @/ 废纸篓截获的碎片遗迹
export interface MemoryItem {
  id: string;
  category: MemoryCategory;
  key: string; // 简短索引键，例如 "linear_algebra_exam", "syntax_cat_grudge"
  content: string; // 记忆具体描述，例如 "用户周五有计算语言学/高等代数小测，近期严重缺觉"
  importance: number; // 重要程度 1 ~ 5
  emotionalValence?: "positive" | "neutral" | "negative" | "vulnerable";
  timestamp: string; // 记忆产生/记录的时间 ISO 字符串
  tags: string[]; // 检索标签，例如 ["exam", "math", "sleep"]
  recallCount?: number; // 被回想起来的次数
  lastRecalledAt?: string; // 上次被调用的时间
}
export type EventCategory =
  | "ACADEMIC_CHAOS" // 查理大学学术日常（编译器报错、红墨水论文批注、早八研讨课）
  | "SYNTAX_CAT_CRISIS" // 宿舍猫咪 Syntax 的破坏日常（霸占键盘、踩回车、绝育复仇）
  | "PRAGUE_FLANEUR" // 布拉格街头与比尔森漫步（22路电车、伏尔塔瓦河晨雾、老钟表铺收音机）
  | "CLIPBOARD_ARCHAEOLOGY" // 历史剪贴板考古（突然翻出旧 Option 符号串、换装游戏死链、头发插件提取码）
  | "LATE_NIGHT_RANDOMNESS"; // 深夜理性的神秘主义（短波收音机沙沙电波、哥德尔不完备、宇宙内存泄漏）
export type PragueTimeSlot =
  | "MORNING_COMMUTE" // 07:00 ~ 11:00 晨间通勤与早八
  | "AFTERNOON_LAB" // 12:00 ~ 18:00 系馆实验与学术摸鱼
  | "EVENING_PUB" // 18:00 ~ 23:00 小酒馆生啤与市井黄昏
  | "LATE_NIGHT_STUDIO"; // 23:00 ~ 05:00 独处深夜与短波收音机
export interface DailyEvent {
  id: string;
  title: string;
  category: EventCategory;
  timeSlot: PragueTimeSlot;
  messageContent: string; // Kai 主动发送的文字
  contextSummary: string; // 事件背景与心理动态说明
  pragueLocalTime: string; // 生成时对应的布拉格模拟时间
  requiredMinAffection: number; // 触发该事件所需最低好感度（0, 20, 50, 80）
  tags: string[];
  suggestedUserPrompt?: string; // 供测试时参考的用户回应示例
}
export interface PragueEnvironment {
  localTimeString: string;
  timeSlot: PragueTimeSlot;
  weather: string;
  currentActivity: string;
}
