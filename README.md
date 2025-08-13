# Decentralized Asset Tracking for Logistics
 
# Decentralized Asset Tracking for Logistics

A Clarity smart contract for transparent tracking of shipping containers and goods across supply chains.

## Overview

This contract provides a decentralized solution for tracking assets throughout their logistics journey. It enables:

- Creation and registration of assets with detailed information
- Authorization of custodians who can handle assets
- Transparent tracking of asset status, location, and custody changes
- Complete immutable history of all asset movements and status updates

## Key Features

- **Asset Registration**: Create new assets with descriptive information
- **Custodian Management**: Register and authorize entities that can handle assets
- **Ownership Control**: Asset owners maintain control over who can be custodians
- **Status Updates**: Authorized custodians can update asset status and location
- **Custody Transfer**: Transparent handoffs between authorized custodians
- **Immutable History**: Complete audit trail of all asset movements and status changes

## Contract Functions

### Custodian Management

```clarity
(register-custodian (name (string-ascii 64)) (role (string-ascii 32)))
```
Registers the caller as a custodian in the system.

### Asset Management

```clarity
(create-asset (name (string-ascii 64)) (description (string-ascii 256)) (location (string-ascii 100)))
```
Creates a new asset with the caller as both owner and initial custodian.

```clarity
(authorize-custodian (asset-id uint) (custodian principal))
```
Authorizes a custodian to handle a specific asset (owner only).

```clarity
(revoke-custodian (asset-id uint) (custodian principal))
```
Revokes a custodian's authorization for a specific asset (owner only).

### Asset Tracking

```clarity
(update-asset-status (asset-id uint) (status (string-ascii 20)) (location (string-ascii 100)) (notes (string-ascii 256)))
```
Updates an asset's status and location (authorized custodians only).

```clarity
(transfer-asset (asset-id uint) (new-custodian principal) (location (string-ascii 100)) (notes (string-ascii 256)))
```
Transfers custody of an asset to another authorized custodian.

### Read-Only Functions

```clarity
(get-asset (asset-id uint))
```
Returns information about a specific asset.

```clarity
(get-asset-history (asset-id uint) (timestamp uint))
```
Returns historical information about an asset at a specific timestamp.

```clarity
(get-custodian (custodian principal))
```
Returns information about a registered custodian.

```clarity
(is-authorized-custodian (asset-id uint) (custodian principal))
```
Checks if a custodian is authorized for a specific asset.

## Usage Example

1. Register as a custodian:
   ```clarity
   (contract-call? .asset-tracking register-custodian "Acme Logistics" "Shipper")
   ```

2. Create a new asset:
   ```clarity
   (contract-call? .asset-tracking create-asset "Container XYZ123" "Electronics shipment" "Port of Shanghai")
   ```

3. Authorize another custodian:
   ```clarity
   (contract-call? .asset-tracking authorize-custodian u1 'ST1J4G6RR643BCG8G8SR6M2D9Z9KXT2NJDRK3FBTK)
   ```

4. Update asset status:
   ```clarity
   (contract-call? .asset-tracking update-asset-status u1 "in-transit" "Pacific Ocean" "Departed port on schedule")
   ```

5. Transfer asset to another custodian:
   ```clarity
   (contract-call? .asset-tracking transfer-asset u1 'ST1J4G6RR643BCG8G8SR6M2D9Z9KXT2NJDRK3FBTK "Port of Los Angeles" "Custody transferred to port authority")
   ```
```
