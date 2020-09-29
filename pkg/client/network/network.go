package network

import (
	"fmt"
	"github.com/IBM-Cloud/power-go-client/clients/instance"
	"github.com/IBM-Cloud/power-go-client/errors"
	"github.com/IBM-Cloud/power-go-client/ibmpisession"
	"github.com/IBM-Cloud/power-go-client/power/client/p_cloud_networks"
	"github.com/IBM-Cloud/power-go-client/power/models"
	"github.com/ppc64le-cloud/pvsadm/pkg"
	"k8s.io/klog/v2"
	"time"
)

type Client struct {
	session    *ibmpisession.IBMPISession
	client     *instance.IBMPINetworkClient
	instanceID string
}

func NewClient(sess *ibmpisession.IBMPISession, powerinstanceid string) *Client {
	c := &Client{
		session:    sess,
		instanceID: powerinstanceid,
	}
	c.client = instance.NewIBMPINetworkClient(sess, powerinstanceid)
	return c
}

func (c *Client) Get(id string) (*models.Network, error) {
	return c.client.Get(id, c.instanceID, pkg.TIMEOUT)
}

func (c *Client) GetPublic() (*models.Networks, error) {
	return c.client.GetPublic(c.instanceID, pkg.TIMEOUT)
}

func (c *Client) GetAll() (*models.Networks, error) {
	params := p_cloud_networks.NewPcloudNetworksGetallParamsWithTimeout(pkg.TIMEOUT).WithCloudInstanceID(c.instanceID)
	resp, err := c.session.Power.PCloudNetworks.PcloudNetworksGetall(params, ibmpisession.NewAuth(c.session, c.instanceID))

	if err != nil || resp.Payload == nil {
		klog.Infof("Failed to perform the operation... %v", err)
		return nil, errors.ToError(err)
	}

	return resp.Payload, nil
}

func (c *Client) Delete(id string) error {
	return c.client.Delete(id, c.instanceID, pkg.TIMEOUT)
}

func (c *Client) GetAllPurgeable(before, since time.Duration) ([]*models.NetworkReference, error) {
	networks, err := c.GetAll()
	if err != nil {
		return nil, fmt.Errorf("failed to get the list of instances: %v", err)
	}

	var candidates []*models.NetworkReference
	for _, network := range networks.Networks {
		candidates = append(candidates, network)
	}
	return candidates, nil
}
