import React from 'react';
import Picker from 'emoji-picker-react';

interface EmojiPickerProps {
  onEmojiSelect: (emoji: any) => void;
  theme?: 'light' | 'dark' | 'auto';
}

export const EmojiPickerComponent: React.FC<EmojiPickerProps> = ({ onEmojiSelect, theme = 'dark' }) => {
  return (
    <div className="absolute bottom-full left-0 mb-2 z-50 shadow-2xl rounded-lg overflow-hidden border border-border">
      <Picker 
        onEmojiClick={(emojiData) => onEmojiSelect(emojiData)}
        theme={theme as any} 
        lazyLoadEmojis={true}
        searchPlaceHolder="Search emojis..."
        width={320}
        height={400}
      />
    </div>
  );
};
