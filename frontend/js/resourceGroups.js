// Resource Groups management functions

async function loadResourceGroups() {
    const resourceGroupsElement = document.getElementById("resourceGroups");
    
    // Show loading state
    showLoading("resourceGroups", "Loading resource groups...");
    
    try {
        const response = await fetch("/resource-groups");        if (!response.ok) {
            if (resourceGroupsElement) {
                resourceGroupsElement.innerHTML =
                    "<div class='alert alert-warning'><i class=\"bi bi-exclamation-triangle-fill me-2\"></i>Error loading resource groups. Is Azure CLI logged in?</div>";
            }
            return;
        }
          const resourceGroups = await response.json();
        
        const resourceGroupList = document.getElementById("resourceGroups");
        if (resourceGroupList) {
            resourceGroupList.innerHTML = "";
            if (resourceGroups.length === 0) {
                resourceGroupList.innerHTML = "<p class=\"text-muted\" style=\"text-align: center; padding: 20px;\"><i class=\"bi bi-diagram-3\" style=\"font-size: 2rem; display: block; margin-bottom: 10px;\"></i>No resource groups found.</p>";
            } else {
                const listHtml = resourceGroups
                    .map(
                        (rg) => `
                        <li class="list-group-item d-flex justify-content-between align-items-center">
                            <div>
                                <strong>${rg.name}</strong>
                                <br />
                                <small class="text-muted">${rg.location || "Unknown location"}</small>
                            </div>
                            <div>
                                <button class="btn btn-sm btn-outline-primary view-rg" data-rg-name="${rg.name}">View Resources</button>
                                <button class="btn btn-sm btn-outline-danger delete-rg" data-rg-name="${rg.name}">Delete</button>
                            </div>
                        </li>
                    `
                    )
                    .join("");
                resourceGroupList.innerHTML = `<ul class="list-group">${listHtml}</ul>`;

                // View resources event
                document.querySelectorAll(".view-rg").forEach((button) => {
                    button.addEventListener("click", (e) => {
                        const rgName = e.target.getAttribute("data-rg-name");
                        viewResourceGroupResources(rgName);
                    });
                });
                
                // Delete resource group event with confirmation
                document.querySelectorAll(".delete-rg").forEach((button) => {
                button.addEventListener("click", async (e) => {
                    const rgName = e.target.getAttribute("data-rg-name");
                    
                    // Show confirmation dialog
                    const confirmed = await showConfirmDialog(
                        'Delete Resource Group',
                        `Are you sure you want to delete resource group '<strong>${rgName}</strong>'?<br><br>
                        <span class="text-danger"><i class="bi bi-exclamation-triangle-fill me-1"></i>
                        This action cannot be undone and will delete all resources in this group!</span>`,
                        'Delete',
                        'Cancel'
                    );
                    
                    if (!confirmed) return;
                      const subscription = document.getElementById("subscription")?.value || "";
                    
                    if (!subscription) {
                        showError("Please select a subscription first");                        return;
                    }                    
                    // Show progress dialog
                    const progressDialog = showProgressDialog(
                        'Deleting Resource Group',
                        `Deleting resource group '${rgName}'... This may take several minutes.`
                    );
                    
                    try {
                        const response = await fetch(`/resource-groups/${rgName}?subscription_id=${encodeURIComponent(subscription)}`, {
                            method: 'DELETE',
                            headers: {
                                'Content-Type': 'application/json'
                            }
                        });
                        
                        if (!response.ok) {
                            const errorText = await response.text();
                            throw new Error(`Failed to delete resource group: ${errorText}`);
                        }

                        progressDialog.close();
                        showSuccess(`Resource group '${rgName}' deletion initiated successfully.`);
                        
                        // Reload resource groups after a delay
                        setTimeout(() => {
                            loadResourceGroups();
                        }, 2000);                    } catch (error) {
                        progressDialog.close();
                        showError('Failed to delete resource group: ' + error.message);
                    }});
            });
            }
        }    } catch (error) {
        showError('Failed to load resource groups: ' + error.message);
    }
}

async function viewResourceGroupResources(rgName) {
    try {
        const response = await fetch(`/resource-groups/${rgName}/resources`);        if (!response.ok) {
            const resourceGroupList = document.getElementById("resourceGroups");
            if (resourceGroupList) {
                resourceGroupList.innerHTML = `<h3>Resources in ${rgName}</h3><p><i class=\"bi bi-exclamation-triangle-fill me-2\"></i>Error loading resources. Is Azure CLI logged in and have you selected the correct subscription?</p>`;
                resourceGroupList.innerHTML +=
                    '<button class="btn btn-secondary mt-3" onclick="loadResourceGroups()">Back to Resource Groups</button>';
            }
            return;
        }const resourceData = await response.json();
        const resources = resourceData.resources || [];  // Extract the resources array
        const resourceGroupList = document.getElementById("resourceGroups");
        if (resourceGroupList) {
            resourceGroupList.innerHTML = `<h3>Resources in ${rgName}</h3>`;
            if (resources.length === 0) {
                resourceGroupList.innerHTML += "<p class=\"text-muted\" style=\"text-align: center; padding: 20px;\"><i class=\"bi bi-box\" style=\"font-size: 2rem; display: block; margin-bottom: 10px;\"></i>No resources found in this resource group.</p>";
            } else {
                const listHtml = resources
                    .map(
                        (res) => `
                    <li class="list-group-item">
                        ${res.name} (${res.type}) - ${res.location}
                    </li>
                `
                    )
                    .join("");
                resourceGroupList.innerHTML += `<ul class="list-group">${listHtml}</ul>`;
            }
            resourceGroupList.innerHTML +=
                '<button class="btn btn-secondary mt-3" onclick="loadResourceGroups()">Back to Resource Groups</button>';
        }    } catch (error) {
        showError('Failed to load resource group resources: ' + error.message);
    }
}

async function createResourceGroup() {
    const name = document.getElementById('newResourceGroupName').value;
    const location = document.getElementById('newResourceGroupLocation').value;
    
    // Try to get subscription from modal first, then fallback to main form
    let subscription = document.getElementById('newResourceGroupSubscription').value;
    if (!subscription) {
        subscription = document.getElementById('subscription').value;
    }

    if (!name || !location) {
        showError('Please fill in the resource group name and location');
        return;
    }

    if (!subscription) {
        showError('Please select a subscription');
        return;
    }

    try {
        const response = await fetch('/resource-groups', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                name: name,
                location: location,
                subscription_id: subscription
            })
        });

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`Failed to create resource group: ${errorText}`);
        }        const result = await response.json();
        
        showSuccess(`Resource group '${name}' created successfully!`);
        
        // Hide the modal
        const createResourceGroupModal = bootstrap.Modal.getInstance(document.getElementById('createResourceGroupModal'));
        if (createResourceGroupModal) {
            createResourceGroupModal.hide();
        }
        
        // Clear the form
        document.getElementById('newResourceGroupName').value = '';
        document.getElementById('newResourceGroupLocation').value = '';
        document.getElementById('newResourceGroupSubscription').value = '';
          // Reload resource groups
        loadResourceGroups();    } catch (error) {
        showError('Failed to create resource group: ' + error.message);
    }
}
