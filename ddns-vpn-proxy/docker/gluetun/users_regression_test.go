package alpine

import (
	"os/user"
	"testing"
)

func TestCreateUserReturnsExistingMatchingUsername(t *testing.T) {
	t.Parallel()

	alpine := &Alpine{
		lookupID: func(uid string) (*user.User, error) {
			if uid != "1000" {
				t.Fatalf("unexpected UID lookup: %s", uid)
			}
			return &user.User{Username: "nonrootuser", Uid: uid}, nil
		},
		lookup: func(username string) (*user.User, error) {
			t.Fatalf("unexpected username lookup: %s", username)
			return nil, nil
		},
	}

	username, err := alpine.CreateUser("nonrootuser", 1000)
	if err != nil {
		t.Fatal(err)
	}
	if username != "nonrootuser" {
		t.Fatalf("matching user returned %q; want nonrootuser", username)
	}
}
