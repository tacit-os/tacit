package backend

import (
	"context"
	"database/sql"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

//go:embed seed-assets/rich-text.html
var seedRichText string

//go:embed seed-assets/funny-cat-52.gif
var seedGIF []byte

//go:embed seed-assets/roastmarket.html
var seedNewsletter string

//go:embed seed-assets/newsletter-* seed-assets/mailbox.json seed-assets/mailbox/*
var seedNewsletterImages embed.FS

func (s *Store) seedMailboxFixtures(ctx context.Context, tx *sql.Tx, fresh bool) error {
	type fixture struct {
		Message
		Files []struct {
			Attachment
			Asset string `json:"asset"`
		} `json:"attachments"`
	}
	data, err := seedNewsletterImages.ReadFile("seed-assets/mailbox.json")
	if err != nil {
		return err
	}
	var fixtures []fixture
	if err = json.Unmarshal(data, &fixtures); err != nil {
		return err
	}
	for _, entry := range fixtures {
		message := entry.Message
		message.RemoteID = "fixture-" + message.ID
		if message.AccountID == "work" {
			message.To = []Address{{Name: "Lorenz", Email: "lorenz@tacit.example"}}
		} else {
			message.To = []Address{{Name: "Lorenz", Email: "lorenz@example.com"}}
		}
		if strings.HasPrefix(message.ID, "seed-") && len(message.ID) == len("seed-00") {
			// These identifiers existed in the original seed. Skip all of them
			// on upgrade, even if the user has removed a message.
			if !fresh {
				continue
			}
			message.RemoteID = "fixture-" + strings.TrimPrefix(message.ID, "seed-")
		}
		for _, file := range entry.Files {
			attachment := file.Attachment
			attachment.Data, err = seedNewsletterImages.ReadFile("seed-assets/" + file.Asset)
			if err != nil {
				return err
			}
			message.Attachments = append(message.Attachments, attachment)
		}
		if err = s.writeSeedFixture(ctx, tx, message); err != nil {
			return err
		}
	}
	return nil
}

// writeSeedFixture adds a fixture only when its identity is absent.
func (s *Store) writeSeedFixture(ctx context.Context, tx *sql.Tx, message Message) error {
	var exists int
	err := tx.QueryRowContext(ctx, `SELECT EXISTS(
        SELECT 1 FROM messages WHERE id = ? OR (account_id = ? AND remote_id = ?)
    )`, message.ID, message.AccountID, message.RemoteID).Scan(&exists)
	if err != nil || exists != 0 {
		return err
	}
	return s.write(ctx, tx, normalise(message))
}

// Seed is deliberately one-shot: restarting never resets user edits.
func (s *Store) Seed(ctx context.Context) error {
	tx, e := s.db.BeginTx(ctx, nil)
	if e != nil {
		return e
	}
	defer tx.Rollback()
	var marker string
	e = tx.QueryRowContext(ctx, `SELECT value FROM metadata WHERE key='seed'`).Scan(&marker)
	if e == nil && marker != "1" {
		return nil
	}
	fresh := errors.Is(e, sql.ErrNoRows)
	if e != nil && !fresh {
		return e
	}
	if fresh {
		for _, a := range []Account{{"work", "Lorenz Rosenthal", "lorenz@tacit.example", "mock"}, {"personal", "Lorenz Rosenthal", "lorenz@example.com", "mock"}} {
			if _, e = tx.ExecContext(ctx, `INSERT INTO accounts VALUES(?,?,?,?) ON CONFLICT(id) DO NOTHING`, a.ID, a.Name, a.Email, a.Provider); e != nil {
				return e
			}
		}
		names := []string{"Lena Fischer", "Nils Berger", "Mara Klein", "Tactical Studio", "Nils Berger", "Quiet Hours", "Studio Newsletter", "Anna Richter", "Jonas Weber", "Clara Neumann", "Research circle", "Felix Braun", "Mara Klein", "Lea Hoffmann"}
		subjects := []string{"The Dusk and Moss pass", "The Dusk and Moss pass", "The Dusk and Moss pass", "Monday notes, prototype review", "Train details for Friday", "Your weekly summary", "A few things worth reading", "A small question about Tuesday", "Lunch next week?", "Dinner on Saturday", "Notes from our last session", "Photos from the coast", "Re: The Dusk and Moss pass", "Your booking confirmation"}
		bodies := []string{"Here are the two palettes as we left them on Friday.", "The moss reads well on dark. The header spacing still feels tight.", "Hi Lorenz,\n\nThe final design review is ready. I have attached the summary and palette notes. Can you send your feedback before Thursday?\n\nThanks,\nMara", "Good morning! Here is this week's prototype review. The next review is on Monday.", "Hi Lorenz, the train leaves at 08:32 on Friday. Your ticket is attached.", "Your week at a glance: three quiet mornings and a little more time for reading.", "This month: small tools, thoughtful interfaces and a few good books.", "Hello Lorenz, would Tuesday afternoon work for a short call?", "Would Wednesday work for lunch? Same place as last time?", "Shall we bring something for dinner? Looking forward to seeing everyone.", "Thanks for joining. These are the notes and references from our discussion.", "Here are the photographs from our walk along the coast.", "Hi Mara, thank you! I will send my notes tomorrow.", "Your reservation is confirmed. Arrival on Friday after 15:00."}
		for i, name := range names {
			// These messages have the full frontend fixtures below, including their original files.
			switch i {
			case 2, 3, 4, 5, 6, 7, 11, 13:
				continue
			}

			account := "work"
			if i >= 5 && i != 6 && i != 10 && i != 12 {
				account = "personal"
			}
			conv := fmt.Sprintf("thread-%02d", i)
			if i < 3 || i == 12 {
				conv = "review"
			}
			date := time.Date(2026, 11, 2, 9, 42, 0, 0, time.UTC).Add(-time.Duration(i) * 7 * time.Hour)
			if i < 3 {
				date = time.Date(2026, 11, 2, 9, 42, 0, 0, time.UTC).Add(time.Duration(i-2) * 24 * time.Hour)
			}
			m := Message{ID: fmt.Sprintf("seed-%02d", i), AccountID: account, RemoteID: fmt.Sprintf("fixture-%02d", i), ConversationID: conv, From: Address{name, fmt.Sprintf("sender%d@example.com", i)}, To: []Address{{Name: "Lorenz", Email: "lorenz@tacit.example"}}, Subject: subjects[i], BodyText: bodies[i], Mailbox: "Inbox", Unread: i == 2 || i == 3 || i == 6, Flagged: i == 4, Date: date}
			if account == "personal" {
				m.To[0].Email = "lorenz@example.com"
			}
			if i == 12 {
				m.From = Address{"Lorenz Rosenthal", "lorenz@tacit.example"}
				m.To = []Address{{"Mara Klein", "mara@example.com"}}
				m.Mailbox = "Sent"
			}
			m = normalise(m)
			if e = s.write(ctx, tx, m); e != nil {
				return e
			}
		}
	}
	if e = s.seedMailboxFixtures(ctx, tx, fresh); e != nil {
		return e
	}
	if e = s.writeSeedFixture(ctx, tx, Message{
		ID: "seed-rich-text", AccountID: "work", RemoteID: "fixture-rich-text",
		ConversationID: "rich-text", From: Address{"Moss Studio", "moss.studio@example.com"},
		Subject:  "Rich-Text-Beispiel · Notizen zur Designrunde",
		BodyText: "Hallo Lorenz,\n\nDie Designrunde ist am Donnerstag. Bitte prüfe bis dahin den Mail-Editor.",
		BodyHTML: seedRichText, Mailbox: "Inbox",
		Date:        time.Date(2026, 11, 1, 12, 30, 0, 0, time.UTC),
		Attachments: []Attachment{{ID: "seed-rich-text-gif", Filename: "funny-cat-52.gif", MediaType: "image/gif", Data: seedGIF}},
	}); e != nil {
		return e
	}
	entries, e := seedNewsletterImages.ReadDir("seed-assets")
	if e != nil {
		return e
	}
	var newsletterAttachments []Attachment
	for _, entry := range entries {
		name := entry.Name()
		if !strings.HasPrefix(name, "newsletter-") {
			continue
		}
		data, err := seedNewsletterImages.ReadFile("seed-assets/" + name)
		if err != nil {
			return err
		}
		newsletterAttachments = append(newsletterAttachments, Attachment{
			ID: "seed-" + name, Filename: name, MediaType: "image/" + strings.Split(name, ".")[1], Data: data,
		})
	}
	if e = s.writeSeedFixture(ctx, tx, Message{
		ID: "seed-roastmarket", AccountID: "personal", RemoteID: "fixture-roastmarket",
		ConversationID: "roastmarket", From: Address{"Roastmarket", "newsletter@example.com"},
		Subject: "Roastmarket Newsletter", BodyText: "Hallo Kaffeefan, entdecke die aktuellen Kaffeeangebote.",
		BodyHTML: seedNewsletter, Attachments: newsletterAttachments, Mailbox: "Inbox", Date: time.Date(2026, 10, 12, 10, 30, 0, 0, time.UTC),
	}); e != nil {
		return e
	}
	if _, e = tx.ExecContext(ctx, `INSERT INTO metadata VALUES('seed','2') ON CONFLICT(key) DO UPDATE SET value=excluded.value`); e != nil {
		return e
	}
	return tx.Commit()
}
