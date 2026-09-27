export type MoodType = '平静' | '专注' | '心动' | '困惑' | '微酸' | '失落';

export interface Message {
  id: string;
  sender: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: number;
}

export interface AgentState {
  name: string | null;
  resonanceRate: number;
  heartRate: number;
  currentMood: MoodType;
  currentQuest: {
    id: string;
    title: string;
    description: string;
    completed: boolean;
  };
}
