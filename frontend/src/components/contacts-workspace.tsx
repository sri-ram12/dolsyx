"use client";

import React, { useState, useEffect } from "react";
import {
  Users,
  Search,
  UserPlus,
  Phone,
  Video,
  MessageSquare,
  Star,
  Trash2,
  Loader2,
  X,
  Check,
  UserCheck,
  Sparkles,
} from "lucide-react";
import { useAuth, API_URL, User } from "@/context/auth-context";
import { useTheme } from "@/context/theme-context";
import { useToast } from "@/context/toast-context";
import { getAvatarUrl } from "@/utils/avatar";

interface ContactRecord {
  id: string;
  savedName?: string;
  isFavorite?: boolean;
  contact?: User;
  isNonContact?: boolean;
  unreadCount?: number;
}

interface ContactsWorkspaceProps {
  onStartChat: (targetUser: User) => void;
  onStartCall: (type: "audio" | "video", targetUser: User) => void;
}

export default function ContactsWorkspace({
  onStartChat,
  onStartCall,
}: ContactsWorkspaceProps) {
  const { user, token } = useAuth();
  const { currentTheme } = useTheme();
  const { toast } = useToast();

  const [contacts, setContacts] = useState<ContactRecord[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [activeFilter, setActiveFilter] = useState<"ALL" | "CONTACTS" | "NON_CONTACTS" | "FAVOURITES" | "UNREAD">("ALL");
  const [searchQuery, setSearchQuery] = useState("");

  // Add Contact Modal State
  const [showAddModal, setShowAddModal] = useState(false);
  const [addIdentifier, setAddIdentifier] = useState("");
  const [addSavedName, setAddSavedName] = useState("");
  const [isAdding, setIsAdding] = useState(false);
  const [addError, setAddError] = useState("");

  const fetchContacts = async () => {
    if (!token) return;
    setIsLoading(true);
    try {
      const res = await fetch(`${API_URL}/api/contacts`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const data = await res.json();
        setContacts(data);
      }
    } catch (e) {
      console.error("Error fetching contacts:", e);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchContacts();
  }, [token]);

  const handleAddContact = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!addIdentifier.trim() || !token) return;
    setIsAdding(true);
    setAddError("");

    try {
      const res = await fetch(`${API_URL}/api/contacts`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          identifier: addIdentifier.trim(),
          savedName: addSavedName.trim() || undefined,
        }),
      });

      const data = await res.json();
      if (res.ok) {
        toast("Contact added successfully!", "success");
        setShowAddModal(false);
        setAddIdentifier("");
        setAddSavedName("");
        fetchContacts();
      } else {
        setAddError(data.message || "Failed to add contact");
      }
    } catch (err) {
      setAddError("Network error adding contact");
    } finally {
      setIsAdding(false);
    }
  };

  const handleDeleteContact = async (contactId: string) => {
    if (!token) return;
    try {
      const res = await fetch(`${API_URL}/api/contacts/${contactId}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        toast("Contact removed", "success");
        setContacts((prev) => prev.filter((c) => c.id !== contactId));
      }
    } catch (e) {
      console.error(e);
    }
  };

  const handleToggleFavorite = async (contact: ContactRecord) => {
    if (!token) return;
    const newFav = !contact.isFavorite;
    try {
      await fetch(`${API_URL}/api/contacts/${contact.id}`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ isFavorite: newFav }),
      });
      setContacts((prev) =>
        prev.map((c) => (c.id === contact.id ? { ...c, isFavorite: newFav } : c))
      );
    } catch (e) {
      console.error(e);
    }
  };

  // Filter & Search Logic (Matching Android ContactsScreen)
  const filteredContacts = contacts.filter((item) => {
    // Filter by tab
    if (activeFilter === "CONTACTS" && item.isNonContact) return false;
    if (activeFilter === "NON_CONTACTS" && !item.isNonContact) return false;
    if (activeFilter === "FAVOURITES" && !item.isFavorite) return false;
    if (activeFilter === "UNREAD" && (item.unreadCount || 0) <= 0) return false;

    // Search query
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      const nameMatch = (item.savedName || item.contact?.username || "").toLowerCase().includes(q);
      const emailMatch = (item.contact?.email || "").toLowerCase().includes(q);
      return nameMatch || emailMatch;
    }
    return true;
  });

  return (
    <div className="flex flex-col h-full w-full bg-[var(--theme-bg-app)] text-[var(--theme-text-primary)] overflow-hidden">
      
      {/* Header */}
      <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-header)] backdrop-blur-md">
        <div className="flex items-center gap-3">
          <div className="p-2 rounded-xl bg-[var(--theme-primary)]/20 text-[var(--theme-primary)]">
            <Users className="h-6 w-6" />
          </div>
          <div>
            <h2 className="font-extrabold text-lg tracking-wide">Contacts</h2>
            <p className="text-xs text-[var(--theme-text-secondary)]">
              {contacts.length} total connections
            </p>
          </div>
        </div>

        <button
          onClick={() => setShowAddModal(true)}
          className="flex items-center gap-2 px-4 py-2 rounded-xl bg-[var(--theme-primary)] text-white text-xs font-bold hover:opacity-90 transition-all cursor-pointer shadow-md"
        >
          <UserPlus className="h-4 w-4" />
          Add Contact
        </button>
      </div>

      {/* Filter Tabs & Search Bar */}
      <div className="p-4 border-b border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] space-y-3">
        {/* Search */}
        <div className="relative max-w-xl">
          <Search className="absolute left-3.5 top-3 h-4 w-4 text-[var(--theme-text-secondary)]" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search contacts by name or email..."
            className="w-full pl-10 pr-4 py-2 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] text-sm text-[var(--theme-text-primary)] placeholder-[var(--theme-text-secondary)]/50 focus:outline-none focus:border-[var(--theme-primary)]"
          />
        </div>

        {/* Filter Pills (Matching Android ContactsScreen) */}
        <div className="flex items-center gap-2 overflow-x-auto pb-1 text-xs font-bold">
          {[
            { id: "ALL", label: "All Contacts" },
            { id: "CONTACTS", label: "Saved" },
            { id: "FAVOURITES", label: "Favorites" },
            { id: "NON_CONTACTS", label: "Direct Chats" },
            { id: "UNREAD", label: "Unread" },
          ].map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveFilter(tab.id as any)}
              className={`px-3 py-1.5 rounded-lg border transition-all cursor-pointer whitespace-nowrap ${
                activeFilter === tab.id
                  ? "bg-[var(--theme-primary)] text-white border-transparent shadow-sm"
                  : "border-[var(--theme-border-color)] text-[var(--theme-text-secondary)] hover:text-white hover:bg-white/5"
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      {/* Contacts List Stream */}
      <div className="flex-1 overflow-y-auto p-4 sm:p-6">
        {isLoading ? (
          <div className="flex items-center justify-center h-48">
            <Loader2 className="h-6 w-6 animate-spin text-[var(--theme-primary)]" />
          </div>
        ) : filteredContacts.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-64 text-center">
            <Users className="h-12 w-12 text-[var(--theme-text-secondary)]/40 mb-3" />
            <h4 className="font-bold text-sm">No contacts found</h4>
            <p className="text-xs text-[var(--theme-text-secondary)] mt-1 max-w-sm">
              {searchQuery
                ? "Try searching for a different username or email."
                : "Add your friends and teammates to connect instantly."}
            </p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
            {filteredContacts.map((c) => {
              const u = c.contact;
              if (!u) return null;
              const displayName = c.savedName || u.username;

              return (
                <div
                  key={c.id}
                  className="flex items-center justify-between p-3.5 rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] hover:border-[var(--theme-primary)]/40 transition-all group shadow-sm"
                >
                  <div className="flex items-center gap-3 min-w-0">
                    <img
                      src={getAvatarUrl(u.avatarUrl, u.username)}
                      alt={displayName}
                      className="w-12 h-12 rounded-full border border-[var(--theme-border-color)] object-cover bg-zinc-800 shrink-0"
                    />
                    <div className="min-w-0">
                      <div className="flex items-center gap-1.5">
                        <h4 className="font-bold text-sm truncate text-[var(--theme-text-primary)]">
                          {displayName}
                        </h4>
                        {c.isFavorite && (
                          <Star className="h-3.5 w-3.5 text-amber-400 fill-amber-400 shrink-0" />
                        )}
                      </div>
                      <p className="text-xs text-[var(--theme-text-secondary)] truncate">
                        {u.bio || u.email || "DOLSYX Member"}
                      </p>
                    </div>
                  </div>

                  {/* Actions */}
                  <div className="flex items-center gap-1.5 shrink-0 ml-2">
                    <button
                      onClick={() => handleToggleFavorite(c)}
                      className={`p-2 rounded-xl transition-colors cursor-pointer ${
                        c.isFavorite
                          ? "text-amber-400 hover:bg-amber-400/10"
                          : "text-[var(--theme-text-secondary)] hover:text-amber-400 hover:bg-white/10"
                      }`}
                      title={c.isFavorite ? "Remove from Favorites" : "Add to Favorites"}
                    >
                      <Star className={`h-4 w-4 ${c.isFavorite ? "fill-amber-400" : ""}`} />
                    </button>

                    <button
                      onClick={() => onStartChat(u)}
                      className="p-2 rounded-xl text-[var(--theme-primary)] hover:bg-[var(--theme-primary)]/15 transition-colors cursor-pointer"
                      title="Send Message"
                    >
                      <MessageSquare className="h-4 w-4" />
                    </button>

                    <button
                      onClick={() => onStartCall("audio", u)}
                      className="p-2 rounded-xl text-green-400 hover:bg-green-400/15 transition-colors cursor-pointer"
                      title="Audio Call"
                    >
                      <Phone className="h-4 w-4" />
                    </button>

                    <button
                      onClick={() => onStartCall("video", u)}
                      className="p-2 rounded-xl text-blue-400 hover:bg-blue-400/15 transition-colors cursor-pointer"
                      title="Video Call"
                    >
                      <Video className="h-4 w-4" />
                    </button>

                    <button
                      onClick={() => handleDeleteContact(c.id)}
                      className="p-2 rounded-xl text-red-400 opacity-0 group-hover:opacity-100 hover:bg-red-500/10 transition-all cursor-pointer"
                      title="Delete Contact"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Add Contact Modal */}
      {showAddModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-sm p-4 animate-fade-in">
          <div className="w-full max-w-md rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] p-6 shadow-2xl space-y-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <UserPlus className="h-5 w-5 text-[var(--theme-primary)]" />
                <h3 className="font-extrabold text-base">Add New Contact</h3>
              </div>
              <button
                onClick={() => setShowAddModal(false)}
                className="p-1 rounded-lg hover:bg-white/10 text-[var(--theme-text-secondary)]"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <p className="text-xs text-[var(--theme-text-secondary)]">
              Enter the username or registered email address of the person you'd like to add.
            </p>

            <form onSubmit={handleAddContact} className="space-y-3">
              <div>
                <label className="text-[10px] font-bold text-[var(--theme-text-secondary)] uppercase">
                  Username or Email
                </label>
                <input
                  type="text"
                  required
                  value={addIdentifier}
                  onChange={(e) => setAddIdentifier(e.target.value)}
                  placeholder="e.g. john_doe or user@dolsyx.com"
                  className="w-full mt-1 px-3.5 py-2.5 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] text-sm text-[var(--theme-text-primary)] focus:outline-none focus:border-[var(--theme-primary)]"
                />
              </div>

              <div>
                <label className="text-[10px] font-bold text-[var(--theme-text-secondary)] uppercase">
                  Custom Nickname (Optional)
                </label>
                <input
                  type="text"
                  value={addSavedName}
                  onChange={(e) => setAddSavedName(e.target.value)}
                  placeholder="e.g. Johnny"
                  className="w-full mt-1 px-3.5 py-2.5 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-search)] text-sm text-[var(--theme-text-primary)] focus:outline-none focus:border-[var(--theme-primary)]"
                />
              </div>

              {addError && (
                <div className="p-2.5 rounded-xl bg-red-500/10 border border-red-500/30 text-xs text-red-400 text-center">
                  {addError}
                </div>
              )}

              <div className="flex items-center justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setShowAddModal(false)}
                  className="px-4 py-2 rounded-xl border border-[var(--theme-border-color)] hover:bg-white/10 text-xs font-bold"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={isAdding || !addIdentifier.trim()}
                  className="px-5 py-2 rounded-xl bg-[var(--theme-primary)] text-white text-xs font-bold hover:opacity-90 disabled:opacity-50 flex items-center gap-1.5 shadow"
                >
                  {isAdding ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Check className="h-3.5 w-3.5" />}
                  Save Contact
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

    </div>
  );
}
