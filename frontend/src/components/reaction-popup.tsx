'use client';

import React from 'react';
import AnimatedEmoji from './animated-emoji';

interface ReactionPopupProps {
  onSelect: (emoji: string) => void;
  onClose: () => void;
}

const QUICK_REACTIONS = ['👍', '❤️', '😂', '😮', '😢', '🙏', '🔥', '🎉'];

export const ReactionPopup: React.FC<ReactionPopupProps> = ({ onSelect, onClose }) => {
  return (
    <div
      className="absolute bottom-full left-0 mb-2 z-50 bg-zinc-900/95 border border-zinc-700/80 shadow-2xl rounded-full flex items-center px-2 py-1 space-x-1 backdrop-blur-md animate-in fade-in zoom-in-95 duration-150"
      onMouseLeave={onClose}
    >
      {QUICK_REACTIONS.map((emoji) => (
        <button
          key={emoji}
          type="button"
          onClick={() => {
            onSelect(emoji);
            onClose();
          }}
          className="p-1.5 rounded-full hover:bg-zinc-800/90 transition-all duration-150 hover:scale-125 active:scale-95 focus:outline-none"
          title={`React with ${emoji}`}
        >
          <AnimatedEmoji emoji={emoji} size="reaction" interactive={false} />
        </button>
      ))}
      <button
        type="button"
        onClick={onClose}
        className="w-7 h-7 flex items-center justify-center rounded-full bg-zinc-800/80 hover:bg-zinc-700 text-zinc-400 hover:text-zinc-200 text-xs font-bold ml-0.5 transition-colors focus:outline-none"
        title="More reactions"
      >
        +
      </button>
    </div>
  );
};
