package regression

import (
	"encoding/json"
	"reflect"
	"testing"

	"github.com/Azure/terraform-provider-azapi/utils"
)

func object(t *testing.T, text string) interface{} {
	t.Helper()
	var value interface{}
	if err := json.Unmarshal([]byte(text), &value); err != nil {
		t.Fatal(err)
	}
	return value
}

// This executes the pinned provider's actual refresh/read-shaping helper.
// It is not a provider HTTP test, Azure persistence test, or state-migration test.
func TestSharingReadShaping(t *testing.T) {
	tests := []struct {
		name, configured, remote string
		equal                    bool
	}{
		{"add_converges", `{"properties":{"sharingProfile":{"subscriptionIds":[{"id":"a"},{"id":"b"}]}}}`, `{"properties":{"sharingProfile":{"subscriptionIds":[{"id":"a"},{"id":"b"}]}}}`, true},
		{"subset_removal_detected", `{"properties":{"sharingProfile":{"subscriptionIds":[{"id":"a"}]}}}`, `{"properties":{"sharingProfile":{"subscriptionIds":[{"id":"a"},{"id":"b"}]}}}`, false},
		{"subset_removal_converges", `{"properties":{"sharingProfile":{"subscriptionIds":[{"id":"a"}]}}}`, `{"properties":{"sharingProfile":{"subscriptionIds":[{"id":"a"}]}}}`, true},
		{"final_clear_detected", `{"properties":{"sharingProfile":{"subscriptionIds":[]}}}`, `{"properties":{"sharingProfile":{"subscriptionIds":[{"id":"a"}]}}}`, false},
		{"final_clear_converges", `{"properties":{"sharingProfile":{"subscriptionIds":[]}}}`, `{"properties":{"sharingProfile":{"subscriptionIds":[]}}}`, true},
		{"restore_converges", `{"properties":{"sharingProfile":{"subscriptionIds":[{"id":"a"},{"id":"b"}]}}}`, `{"properties":{"sharingProfile":{"subscriptionIds":[{"id":"a"},{"id":"b"}]}}}`, true},
		{"same_count_retarget_detected", `{"properties":{"sharingProfile":{"subscriptionIds":[{"id":"c"}]}}}`, `{"properties":{"sharingProfile":{"subscriptionIds":[{"id":"a"}]}}}`, false},
		{"reorder_is_not_hidden", `{"properties":{"sharingProfile":{"subscriptionIds":[{"id":"b"},{"id":"a"}]}}}`, `{"properties":{"sharingProfile":{"subscriptionIds":[{"id":"a"},{"id":"b"}]}}}`, false},
		{"external_member_detected", `{"properties":{"sharingProfile":{"subscriptionIds":[{"id":"a"}]}}}`, `{"properties":{"sharingProfile":{"subscriptionIds":[{"id":"a"},{"id":"external"}]}}}`, false},
		{"unowned_child_projection_omitted", `{"properties":{},"zones":["1"]}`, `{"properties":{"capacityReservations":[{"id":"external-child"}],"virtualMachinesAssociated":[{"id":"external-vm"}]},"zones":["1"]}`, true},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			configured := object(t, test.configured)
			remote := object(t, test.remote)
			shaped := utils.UpdateObject(configured, remote, utils.UpdateJsonOption{IgnoreMissingProperty: true})
			if equal := reflect.DeepEqual(configured, shaped); equal != test.equal {
				t.Fatalf("configuration equality = %v, want %v; shaped response = %#v", equal, test.equal, shaped)
			}
		})
	}
}
