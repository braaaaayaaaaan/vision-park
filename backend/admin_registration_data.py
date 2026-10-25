"""Full-dataset registration statistics using existing read privileges only."""
from uuid import UUID

from pydantic import BaseModel, Field, model_validator


class CompanyRegistrationCounts(BaseModel):
    id: UUID
    name: str
    total: int = Field(ge=0)
    pending: int = Field(ge=0)
    approved: int = Field(ge=0)
    rejected: int = Field(ge=0)


class RegistrationSummary(BaseModel):
    total_registrations: int = Field(ge=0)
    pending_approvals: int = Field(ge=0)
    approved_accounts: int = Field(ge=0)
    rejected_accounts: int = Field(ge=0)
    represented_companies: int = Field(ge=0)
    unassigned_drivers: int = Field(ge=0)
    companies: list[CompanyRegistrationCounts]

    @model_validator(mode='after')
    def consistent(self):
        if self.total_registrations != self.pending_approvals + self.approved_accounts + self.rejected_accounts:
            raise ValueError('Inconsistent registration totals')
        if (sum(company.total for company in self.companies) + self.unassigned_drivers != self.total_registrations
                or self.represented_companies != sum(company.total > 0 for company in self.companies)
                or len({company.id for company in self.companies}) != len(self.companies)
                or any(company.total != company.pending + company.approved + company.rejected for company in self.companies)):
            raise ValueError('Inconsistent company counts')
        return self


def summarize_registrations(rows, companies):
    groups = {str(company['id']): dict(id=company['id'], name=company['name'], total=0, pending=0, approved=0, rejected=0)
              for company in companies}
    totals = dict(pending=0, approved=0, rejected=0)
    seen = set()
    unassigned = 0
    for row in rows:
        if row['id'] in seen:
            raise ValueError('Duplicate driver')
        seen.add(row['id'])
        status = row['approval_status']
        if status not in totals:
            raise ValueError('Invalid driver status')
        totals[status] += 1
        company_id = row.get('tenant_id') if status == 'approved' else row.get('requested_tenant_id')
        group = groups.get(str(company_id)) if company_id else None
        if group is None:
            unassigned += 1
        else:
            group['total'] += 1
            group[status] += 1
    return RegistrationSummary(total_registrations=len(rows), pending_approvals=totals['pending'],
        approved_accounts=totals['approved'], rejected_accounts=totals['rejected'],
        represented_companies=sum(group['total'] > 0 for group in groups.values()), unassigned_drivers=unassigned,
        companies=sorted(groups.values(), key=lambda group: (group['name'].casefold(), str(group['id']))))
