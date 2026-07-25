import React from 'react';
import TwemojiText from './twemoji-text';
interface ReactionPopupProps {
  onSelect: (emoji: string) => void;
  onClose: () => void;
}

const QUICK_REACTIONS = ["👍", "❤️", "😂", "😮", "😢", "🙏"];

export const ReactionPopup: React.FC<ReactionPopupProps> = ({ onSelect, onClose }) => {
  return (
    <div 
      className="absolute bottom-full left-0 mb-1 z-50 bg-background border border-border shadow-lg rounded-full flex items-center p-1 space-x-1"
      onMouseLeave={onClose}
    >
      {QUICK_REACTIONS.map((emoji) => (
        <button
          key={emoji}
          onClick={() => {
            onSelect(emoji);
            onClose();
          }}
          className="hover:scale-125 transition-transform duration-200 focus:outline-none p-1 rounded-full hover:bg-muted"
          style={{ fontSize: "17.5px" }} // 17.5 * 1.375 = 24px Twemoji
        >
          <TwemojiText text={emoji} />
        </button>
      ))}
      <button 
        onClick={() => {
          // Fallback to full picker if needed, but for now just pass a custom one or open the main picker
          onClose();
        }}
        className="w-8 h-8 flex items-center justify-center rounded-full bg-muted hover:bg-secondary text-foreground text-sm font-bold ml-1 transition-colors"
      >
        +
      </button>
    </div>
  );
};
